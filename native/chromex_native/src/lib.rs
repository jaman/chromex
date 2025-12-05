use chroma_config::{registry::Registry, Configurable};
use chroma_frontend::{Frontend, FrontendConfig};
use chroma_frontend::executor::config::{ExecutorConfig, LocalExecutorConfig};
use chroma_log::config::{LogConfig, SqliteLogConfig};
use chroma_segment::local_segment_manager::LocalSegmentManagerConfig;
use chroma_sqlite::config::{SqliteDBConfig, MigrationMode, MigrationHash};
use chroma_sysdb::{SqliteSysDbConfig, SysDbConfig};
use chroma_system::System;
use chroma_types::{
    AddCollectionRecordsRequest, CollectionUuid, CountRequest,
    CreateCollectionRequest, CreateDatabaseRequest, CreateTenantRequest,
    DeleteCollectionRecordsRequest, DeleteCollectionRequest, DeleteDatabaseRequest,
    GetCollectionRequest, GetDatabaseRequest, GetRequest, GetTenantRequest, Include, IncludeList,
    InternalCollectionConfiguration, ListCollectionsRequest, ListDatabasesRequest,
    Metadata, QueryRequest, RawWhereFields, UpdateCollectionRecordsRequest, UpdateCollectionRequest,
    UpsertCollectionRecordsRequest, Where, UpdateMetadata, CollectionMetadataUpdate,
};
use rustler::{Env, Error, NifResult, ResourceArc, Term};
use std::sync::{Arc, Mutex};
use tokio::runtime::Runtime;
use uuid::Uuid;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        nil,
    }
}

struct ChromaBindings {
    runtime: Runtime,
    frontend: Arc<Mutex<Frontend>>,
}

impl ChromaBindings {
    fn new(
        allow_reset: bool,
        persist_path: Option<String>,
    ) -> Result<Self, Box<dyn std::error::Error>> {
        let runtime = Runtime::new()?;

        let storage_path = persist_path.unwrap_or_else(|| "./chroma_data".to_string());
        std::fs::create_dir_all(&storage_path)?;

        let frontend = runtime.block_on(async {
            let system = System::new();
            let registry = Registry::new();

            let db_path = format!("{}/chroma.db", storage_path);

            let sqlite_config = SqliteDBConfig {
                url: Some(db_path),
                hash_type: MigrationHash::MD5,
                migration_mode: MigrationMode::Apply,
            };

            let sysdb_config = SysDbConfig::Sqlite(SqliteSysDbConfig {
                log_topic_namespace: "default".to_string(),
                log_tenant: "default".to_string(),
            });

            let log_config = LogConfig::Sqlite(SqliteLogConfig {
                tenant_id: "default".to_string(),
                topic_namespace: "default".to_string(),
            });

            let segment_manager_config = LocalSegmentManagerConfig {
                hnsw_index_pool_cache_config: chroma_cache::CacheConfig::Memory(
                    chroma_cache::FoyerCacheConfig {
                        capacity: 65536,
                        ..Default::default()
                    },
                ),
                persist_path: Some(storage_path.clone()),
            };

            let fe_config = FrontendConfig {
                allow_reset,
                sqlitedb: Some(sqlite_config),
                segment_manager: Some(segment_manager_config),
                sysdb: sysdb_config,
                collections_with_segments_provider: Default::default(),
                log: log_config,
                executor: ExecutorConfig::Local(LocalExecutorConfig {}),
                default_knn_index: chroma_types::KnnIndex::Hnsw,
                tenants_to_migrate_immediately: vec![],
                tenants_to_migrate_immediately_threshold: None,
                enable_schema: true,
                min_records_for_invocation: 100,
            };

            Frontend::try_from_config(&(fe_config, system.clone()), &registry).await
        })?;

        Ok(ChromaBindings {
            runtime,
            frontend: Arc::new(Mutex::new(frontend)),
        })
    }

    fn parse_metadata(&self, json_str: &str) -> Result<Metadata, Box<dyn std::error::Error>> {
        Ok(serde_json::from_str(json_str)?)
    }

    fn parse_update_metadata(&self, json_str: &str) -> Result<UpdateMetadata, Box<dyn std::error::Error>> {
        Ok(serde_json::from_str(json_str)?)
    }

    fn parse_where(&self, json_str: &str) -> Result<Option<Where>, Box<dyn std::error::Error>> {
        let raw_where = RawWhereFields::from_json_str(Some(json_str), None)?;
        Ok(raw_where.parse()?)
    }
}

struct ChromaBindingsResource {
    inner: Arc<Mutex<ChromaBindings>>,
}

fn on_load(env: Env, _info: Term) -> bool {
    rustler::resource!(ChromaBindingsResource, env);
    true
}

#[rustler::nif]
fn init(
    allow_reset: bool,
    persist_path: Option<String>,
    _hnsw_cache_size: usize,
) -> NifResult<ResourceArc<ChromaBindingsResource>> {
    let bindings = ChromaBindings::new(allow_reset, persist_path)
        .map_err(|e| Error::Term(Box::new(format!("{:?}", e))))?;

    Ok(ResourceArc::new(ChromaBindingsResource {
        inner: Arc::new(Mutex::new(bindings)),
    }))
}

#[rustler::nif]
fn heartbeat() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos() as i64
}

#[rustler::nif]
fn get_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

#[rustler::nif]
fn get_max_batch_size(resource: ResourceArc<ChromaBindingsResource>) -> NifResult<i32> {
    let _bindings = resource.inner.lock().unwrap();
    Ok(40000)
}

#[rustler::nif]
fn create_collection(
    resource: ResourceArc<ChromaBindingsResource>,
    name: String,
    config_json: Option<String>,
    metadata_json: Option<String>,
    get_or_create: bool,
    tenant: String,
    database: String,
) -> NifResult<String> {
    let bindings = resource.inner.lock().unwrap();

    let metadata = if let Some(json) = metadata_json {
        Some(
            bindings
                .parse_metadata(&json)
                .map_err(|e| Error::Term(Box::new(format!("Metadata error: {:?}", e))))?,
        )
    } else {
        None
    };

    let configuration = if let Some(json) = config_json {
        let config: InternalCollectionConfiguration = serde_json::from_str(&json)
            .map_err(|e| Error::Term(Box::new(format!("Config error: {:?}", e))))?;
        Some(config)
    } else {
        None
    };

    let request = CreateCollectionRequest::try_new(
        tenant,
        database,
        name,
        metadata,
        configuration,
        None,
        get_or_create,
    ).map_err(|e| Error::Term(Box::new(format!("Request error: {:?}", e))))?;

    let mut frontend = bindings.frontend.lock().unwrap();
    let result = bindings.runtime.block_on(async {
        frontend.create_collection(request).await
    });

    match result {
        Ok(collection) => {
            let json = serde_json::to_string(&collection)
                .map_err(|e| Error::Term(Box::new(format!("Serialization error: {:?}", e))))?;
            Ok(json)
        }
        Err(e) => Err(Error::Term(Box::new(format!("{:?}", e)))),
    }
}

#[rustler::nif]
fn get_collection(
    resource: ResourceArc<ChromaBindingsResource>,
    name: String,
    tenant: String,
    database: String,
) -> NifResult<String> {
    let bindings = resource.inner.lock().unwrap();

    let request = GetCollectionRequest::try_new(
        tenant,
        database,
        name,
    ).map_err(|e| Error::Term(Box::new(format!("Request error: {:?}", e))))?;

    let mut frontend = bindings.frontend.lock().unwrap();
    let result = bindings.runtime.block_on(async {
        frontend.get_collection(request).await
    });

    match result {
        Ok(collection) => {
            let json = serde_json::to_string(&collection)
                .map_err(|e| Error::Term(Box::new(format!("Serialization error: {:?}", e))))?;
            Ok(json)
        }
        Err(e) => Err(Error::Term(Box::new(format!("{:?}", e)))),
    }
}

#[rustler::nif]
fn delete_collection(
    resource: ResourceArc<ChromaBindingsResource>,
    name: String,
    tenant: String,
    database: String,
) -> NifResult<String> {
    let bindings = resource.inner.lock().unwrap();

    let request = DeleteCollectionRequest::try_new(
        tenant,
        database,
        name,
    ).map_err(|e| Error::Term(Box::new(format!("Request error: {:?}", e))))?;

    let mut frontend = bindings.frontend.lock().unwrap();
    let result = bindings.runtime.block_on(async {
        frontend.delete_collection(request).await
    });

    match result {
        Ok(_) => Ok("ok".to_string()),
        Err(e) => Err(Error::Term(Box::new(format!("{:?}", e)))),
    }
}

#[rustler::nif]
fn list_collections(
    resource: ResourceArc<ChromaBindingsResource>,
    limit: Option<u32>,
    offset: Option<u32>,
    tenant: String,
    database: String,
) -> NifResult<String> {
    let bindings = resource.inner.lock().unwrap();

    let request = ListCollectionsRequest::try_new(
        tenant,
        database,
        limit,
        offset.unwrap_or(0),
    ).map_err(|e| Error::Term(Box::new(format!("Request error: {:?}", e))))?;

    let mut frontend = bindings.frontend.lock().unwrap();
    let result = bindings.runtime.block_on(async {
        frontend.list_collections(request).await
    });

    match result {
        Ok(collections) => {
            let json = serde_json::to_string(&collections)
                .map_err(|e| Error::Term(Box::new(format!("Serialization error: {:?}", e))))?;
            Ok(json)
        }
        Err(e) => Err(Error::Term(Box::new(format!("{:?}", e)))),
    }
}

#[rustler::nif]
fn count_collections(
    resource: ResourceArc<ChromaBindingsResource>,
    tenant: String,
    database: String,
) -> NifResult<i32> {
    let bindings = resource.inner.lock().unwrap();

    let request = ListCollectionsRequest::try_new(
        tenant,
        database,
        None,
        0,
    ).map_err(|e| Error::Term(Box::new(format!("Request error: {:?}", e))))?;

    let mut frontend = bindings.frontend.lock().unwrap();
    let result = bindings.runtime.block_on(async {
        frontend.list_collections(request).await
    });

    match result {
        Ok(collections) => Ok(collections.len() as i32),
        Err(e) => Err(Error::Term(Box::new(format!("{:?}", e)))),
    }
}

#[rustler::nif]
fn add(
    resource: ResourceArc<ChromaBindingsResource>,
    ids: Vec<String>,
    collection_id: String,
    embeddings: Vec<Vec<f32>>,
    metadatas_json: Option<Vec<Option<String>>>,
    documents: Option<Vec<Option<String>>>,
    uris: Option<Vec<Option<String>>>,
    tenant: String,
    database: String,
) -> NifResult<String> {
    let bindings = resource.inner.lock().unwrap();

    let collection_uuid = Uuid::parse_str(&collection_id)
        .map_err(|e| Error::Term(Box::new(format!("UUID error: {:?}", e))))?;

    let parsed_metadatas = if let Some(json_vec) = metadatas_json {
        let mut metadatas = Vec::new();
        for opt_json in json_vec {
            if let Some(json) = opt_json {
                let metadata = bindings
                    .parse_metadata(&json)
                    .map_err(|e| Error::Term(Box::new(format!("Metadata error: {:?}", e))))?;
                metadatas.push(Some(metadata));
            } else {
                metadatas.push(None);
            }
        }
        Some(metadatas)
    } else {
        None
    };

    let request = AddCollectionRecordsRequest::try_new(
        tenant,
        database,
        CollectionUuid(collection_uuid),
        ids,
        embeddings,
        documents,
        uris,
        parsed_metadatas,
    ).map_err(|e| Error::Term(Box::new(format!("Request error: {:?}", e))))?;

    let mut frontend = bindings.frontend.lock().unwrap();
    let result = bindings.runtime.block_on(async {
        frontend.add(request).await
    });

    match result {
        Ok(_) => Ok("ok".to_string()),
        Err(e) => Err(Error::Term(Box::new(format!("{:?}", e)))),
    }
}

#[rustler::nif]
fn query(
    resource: ResourceArc<ChromaBindingsResource>,
    collection_id: String,
    query_embeddings: Vec<Vec<f32>>,
    n_results: u32,
    where_json: Option<String>,
    _where_document_json: Option<String>,
    include: Vec<String>,
    tenant: String,
    database: String,
) -> NifResult<String> {
    let bindings = resource.inner.lock().unwrap();

    let collection_uuid = Uuid::parse_str(&collection_id)
        .map_err(|e| Error::Term(Box::new(format!("UUID error: {:?}", e))))?;

    let parsed_where = if let Some(json) = where_json {
        bindings
            .parse_where(&json)
            .map_err(|e| Error::Term(Box::new(format!("Where error: {:?}", e))))?
    } else {
        None
    };

    let mut include_list = Vec::new();
    if include.contains(&"documents".to_string()) {
        include_list.push(Include::Document);
    }
    if include.contains(&"embeddings".to_string()) {
        include_list.push(Include::Embedding);
    }
    if include.contains(&"metadatas".to_string()) {
        include_list.push(Include::Metadata);
    }
    if include.contains(&"distances".to_string()) {
        include_list.push(Include::Distance);
    }
    if include.contains(&"uris".to_string()) {
        include_list.push(Include::Uri);
    }

    let request = QueryRequest::try_new(
        tenant,
        database,
        CollectionUuid(collection_uuid),
        None,
        parsed_where,
        query_embeddings,
        n_results,
        IncludeList(include_list),
    ).map_err(|e| Error::Term(Box::new(format!("Request error: {:?}", e))))?;

    let mut frontend = bindings.frontend.lock().unwrap();
    let result = bindings.runtime.block_on(async {
        frontend.query(request).await
    });

    match result {
        Ok(query_result) => {
            let json = serde_json::to_string(&query_result)
                .map_err(|e| Error::Term(Box::new(format!("Serialization error: {:?}", e))))?;
            Ok(json)
        }
        Err(e) => Err(Error::Term(Box::new(format!("{:?}", e)))),
    }
}

#[rustler::nif]
fn get(
    resource: ResourceArc<ChromaBindingsResource>,
    collection_id: String,
    ids: Option<Vec<String>>,
    where_json: Option<String>,
    limit: Option<u32>,
    offset: Option<u32>,
    _where_document_json: Option<String>,
    include: Vec<String>,
    tenant: String,
    database: String,
) -> NifResult<String> {
    let bindings = resource.inner.lock().unwrap();

    let collection_uuid = Uuid::parse_str(&collection_id)
        .map_err(|e| Error::Term(Box::new(format!("UUID error: {:?}", e))))?;

    let parsed_where = if let Some(json) = where_json {
        bindings
            .parse_where(&json)
            .map_err(|e| Error::Term(Box::new(format!("Where error: {:?}", e))))?
    } else {
        None
    };

    let mut include_list = Vec::new();
    if include.contains(&"documents".to_string()) {
        include_list.push(Include::Document);
    }
    if include.contains(&"embeddings".to_string()) {
        include_list.push(Include::Embedding);
    }
    if include.contains(&"metadatas".to_string()) {
        include_list.push(Include::Metadata);
    }
    if include.contains(&"distances".to_string()) {
        include_list.push(Include::Distance);
    }
    if include.contains(&"uris".to_string()) {
        include_list.push(Include::Uri);
    }

    let request = GetRequest::try_new(
        tenant,
        database,
        CollectionUuid(collection_uuid),
        ids,
        parsed_where,
        limit,
        offset.unwrap_or(0),
        IncludeList(include_list),
    ).map_err(|e| Error::Term(Box::new(format!("Request error: {:?}", e))))?;

    let mut frontend = bindings.frontend.lock().unwrap();
    let result = bindings.runtime.block_on(async {
        frontend.get(request).await
    });

    match result {
        Ok(get_result) => {
            let json = serde_json::to_string(&get_result)
                .map_err(|e| Error::Term(Box::new(format!("Serialization error: {:?}", e))))?;
            Ok(json)
        }
        Err(e) => Err(Error::Term(Box::new(format!("{:?}", e)))),
    }
}

#[rustler::nif]
fn update(
    resource: ResourceArc<ChromaBindingsResource>,
    collection_id: String,
    ids: Vec<String>,
    embeddings: Option<Vec<Option<Vec<f32>>>>,
    metadatas_json: Option<Vec<Option<String>>>,
    documents: Option<Vec<Option<String>>>,
    uris: Option<Vec<Option<String>>>,
    tenant: String,
    database: String,
) -> NifResult<String> {
    let bindings = resource.inner.lock().unwrap();

    let collection_uuid = Uuid::parse_str(&collection_id)
        .map_err(|e| Error::Term(Box::new(format!("UUID error: {:?}", e))))?;

    let parsed_metadatas = if let Some(json_vec) = metadatas_json {
        let mut metadatas = Vec::new();
        for opt_json in json_vec {
            if let Some(json) = opt_json {
                let metadata = bindings
                    .parse_update_metadata(&json)
                    .map_err(|e| Error::Term(Box::new(format!("Metadata error: {:?}", e))))?;
                metadatas.push(Some(metadata));
            } else {
                metadatas.push(None);
            }
        }
        Some(metadatas)
    } else {
        None
    };

    let request = UpdateCollectionRecordsRequest::try_new(
        tenant,
        database,
        CollectionUuid(collection_uuid),
        ids,
        embeddings,
        documents,
        uris,
        parsed_metadatas,
    ).map_err(|e| Error::Term(Box::new(format!("Request error: {:?}", e))))?;

    let mut frontend = bindings.frontend.lock().unwrap();
    let result = bindings.runtime.block_on(async {
        frontend.update(request).await
    });

    match result {
        Ok(_) => Ok("ok".to_string()),
        Err(e) => Err(Error::Term(Box::new(format!("{:?}", e)))),
    }
}

#[rustler::nif]
fn upsert(
    resource: ResourceArc<ChromaBindingsResource>,
    collection_id: String,
    ids: Vec<String>,
    embeddings: Vec<Vec<f32>>,
    metadatas_json: Option<Vec<Option<String>>>,
    documents: Option<Vec<Option<String>>>,
    uris: Option<Vec<Option<String>>>,
    tenant: String,
    database: String,
) -> NifResult<String> {
    let bindings = resource.inner.lock().unwrap();

    let collection_uuid = Uuid::parse_str(&collection_id)
        .map_err(|e| Error::Term(Box::new(format!("UUID error: {:?}", e))))?;

    let parsed_metadatas = if let Some(json_vec) = metadatas_json {
        let mut metadatas = Vec::new();
        for opt_json in json_vec {
            if let Some(json) = opt_json {
                let metadata = bindings
                    .parse_update_metadata(&json)
                    .map_err(|e| Error::Term(Box::new(format!("Metadata error: {:?}", e))))?;
                metadatas.push(Some(metadata));
            } else {
                metadatas.push(None);
            }
        }
        Some(metadatas)
    } else {
        None
    };

    let request = UpsertCollectionRecordsRequest::try_new(
        tenant,
        database,
        CollectionUuid(collection_uuid),
        ids,
        embeddings,
        documents,
        uris,
        parsed_metadatas,
    ).map_err(|e| Error::Term(Box::new(format!("Request error: {:?}", e))))?;

    let mut frontend = bindings.frontend.lock().unwrap();
    let result = bindings.runtime.block_on(async {
        frontend.upsert(request).await
    });

    match result {
        Ok(_) => Ok("ok".to_string()),
        Err(e) => Err(Error::Term(Box::new(format!("{:?}", e)))),
    }
}

#[rustler::nif]
fn delete(
    resource: ResourceArc<ChromaBindingsResource>,
    collection_id: String,
    ids: Option<Vec<String>>,
    where_json: Option<String>,
    _where_document_json: Option<String>,
    tenant: String,
    database: String,
) -> NifResult<String> {
    let bindings = resource.inner.lock().unwrap();

    let collection_uuid = Uuid::parse_str(&collection_id)
        .map_err(|e| Error::Term(Box::new(format!("UUID error: {:?}", e))))?;

    let parsed_where = if let Some(json) = where_json {
        bindings
            .parse_where(&json)
            .map_err(|e| Error::Term(Box::new(format!("Where error: {:?}", e))))?
    } else {
        None
    };

    let request = DeleteCollectionRecordsRequest::try_new(
        tenant,
        database,
        CollectionUuid(collection_uuid),
        ids,
        parsed_where,
    ).map_err(|e| Error::Term(Box::new(format!("Request error: {:?}", e))))?;

    let mut frontend = bindings.frontend.lock().unwrap();
    let result = bindings.runtime.block_on(async {
        frontend.delete(request).await
    });

    match result {
        Ok(_) => Ok("ok".to_string()),
        Err(e) => Err(Error::Term(Box::new(format!("{:?}", e)))),
    }
}

#[rustler::nif]
fn count(
    resource: ResourceArc<ChromaBindingsResource>,
    collection_id: String,
    tenant: String,
    database: String,
) -> NifResult<i32> {
    let bindings = resource.inner.lock().unwrap();

    let collection_uuid = Uuid::parse_str(&collection_id)
        .map_err(|e| Error::Term(Box::new(format!("UUID error: {:?}", e))))?;

    let request = CountRequest::try_new(
        tenant,
        database,
        CollectionUuid(collection_uuid),
    ).map_err(|e| Error::Term(Box::new(format!("Request error: {:?}", e))))?;

    let mut frontend = bindings.frontend.lock().unwrap();
    let result = bindings.runtime.block_on(async {
        frontend.count(request).await
    });

    match result {
        Ok(count) => Ok(count as i32),
        Err(e) => Err(Error::Term(Box::new(format!("{:?}", e)))),
    }
}

#[rustler::nif]
fn create_database(
    resource: ResourceArc<ChromaBindingsResource>,
    name: String,
    tenant: String,
) -> NifResult<String> {
    let bindings = resource.inner.lock().unwrap();

    let request = CreateDatabaseRequest::try_new(
        tenant,
        name,
    ).map_err(|e| Error::Term(Box::new(format!("Request error: {:?}", e))))?;

    let mut frontend = bindings.frontend.lock().unwrap();
    let result = bindings.runtime.block_on(async {
        frontend.create_database(request).await
    });

    match result {
        Ok(database) => {
            let json = serde_json::to_string(&database)
                .map_err(|e| Error::Term(Box::new(format!("Serialization error: {:?}", e))))?;
            Ok(json)
        }
        Err(e) => Err(Error::Term(Box::new(format!("{:?}", e)))),
    }
}

#[rustler::nif]
fn get_database(
    resource: ResourceArc<ChromaBindingsResource>,
    name: String,
    tenant: String,
) -> NifResult<String> {
    let bindings = resource.inner.lock().unwrap();

    let request = GetDatabaseRequest::try_new(
        tenant,
        name,
    ).map_err(|e| Error::Term(Box::new(format!("Request error: {:?}", e))))?;

    let mut frontend = bindings.frontend.lock().unwrap();
    let result = bindings.runtime.block_on(async {
        frontend.get_database(request).await
    });

    match result {
        Ok(database) => {
            let json = serde_json::to_string(&database)
                .map_err(|e| Error::Term(Box::new(format!("Serialization error: {:?}", e))))?;
            Ok(json)
        }
        Err(e) => Err(Error::Term(Box::new(format!("{:?}", e)))),
    }
}

#[rustler::nif]
fn delete_database(
    resource: ResourceArc<ChromaBindingsResource>,
    name: String,
    tenant: String,
) -> NifResult<String> {
    let bindings = resource.inner.lock().unwrap();

    let request = DeleteDatabaseRequest::try_new(
        tenant,
        name,
    ).map_err(|e| Error::Term(Box::new(format!("Request error: {:?}", e))))?;

    let mut frontend = bindings.frontend.lock().unwrap();
    let result = bindings.runtime.block_on(async {
        frontend.delete_database(request).await
    });

    match result {
        Ok(_) => Ok("ok".to_string()),
        Err(e) => Err(Error::Term(Box::new(format!("{:?}", e)))),
    }
}

#[rustler::nif]
fn list_databases(
    resource: ResourceArc<ChromaBindingsResource>,
    limit: Option<u32>,
    offset: Option<u32>,
    tenant: String,
) -> NifResult<String> {
    let bindings = resource.inner.lock().unwrap();

    let request = ListDatabasesRequest::try_new(
        tenant,
        limit,
        offset.unwrap_or(0),
    ).map_err(|e| Error::Term(Box::new(format!("Request error: {:?}", e))))?;

    let mut frontend = bindings.frontend.lock().unwrap();
    let result = bindings.runtime.block_on(async {
        frontend.list_databases(request).await
    });

    match result {
        Ok(databases) => {
            let json = serde_json::to_string(&databases)
                .map_err(|e| Error::Term(Box::new(format!("Serialization error: {:?}", e))))?;
            Ok(json)
        }
        Err(e) => Err(Error::Term(Box::new(format!("{:?}", e)))),
    }
}

#[rustler::nif]
fn create_tenant(
    resource: ResourceArc<ChromaBindingsResource>,
    name: String,
) -> NifResult<String> {
    let bindings = resource.inner.lock().unwrap();

    let request = CreateTenantRequest::try_new(name)
        .map_err(|e| Error::Term(Box::new(format!("Request error: {:?}", e))))?;

    let mut frontend = bindings.frontend.lock().unwrap();
    let result = bindings.runtime.block_on(async {
        frontend.create_tenant(request).await
    });

    match result {
        Ok(tenant) => {
            let json = serde_json::to_string(&tenant)
                .map_err(|e| Error::Term(Box::new(format!("Serialization error: {:?}", e))))?;
            Ok(json)
        }
        Err(e) => Err(Error::Term(Box::new(format!("{:?}", e)))),
    }
}

#[rustler::nif]
fn get_tenant(
    resource: ResourceArc<ChromaBindingsResource>,
    name: String,
) -> NifResult<String> {
    let bindings = resource.inner.lock().unwrap();

    let request = GetTenantRequest::try_new(name)
        .map_err(|e| Error::Term(Box::new(format!("Request error: {:?}", e))))?;

    let mut frontend = bindings.frontend.lock().unwrap();
    let result = bindings.runtime.block_on(async {
        frontend.get_tenant(request).await
    });

    match result {
        Ok(tenant) => {
            let json = serde_json::to_string(&tenant)
                .map_err(|e| Error::Term(Box::new(format!("Serialization error: {:?}", e))))?;
            Ok(json)
        }
        Err(e) => Err(Error::Term(Box::new(format!("{:?}", e)))),
    }
}

#[rustler::nif]
fn reset(resource: ResourceArc<ChromaBindingsResource>) -> NifResult<String> {
    let bindings = resource.inner.lock().unwrap();

    let mut frontend = bindings.frontend.lock().unwrap();
    let result = bindings.runtime.block_on(async {
        frontend.reset().await
    });

    match result {
        Ok(_) => Ok("ok".to_string()),
        Err(e) => Err(Error::Term(Box::new(format!("{:?}", e)))),
    }
}

#[rustler::nif]
fn update_collection(
    resource: ResourceArc<ChromaBindingsResource>,
    collection_id: String,
    new_name: Option<String>,
    new_metadata_json: Option<String>,
    _new_config_json: Option<String>,
) -> NifResult<String> {
    let bindings = resource.inner.lock().unwrap();

    let collection_uuid = Uuid::parse_str(&collection_id)
        .map_err(|e| Error::Term(Box::new(format!("UUID error: {:?}", e))))?;

    let parsed_metadata = if let Some(json) = new_metadata_json {
        let metadata = bindings
            .parse_update_metadata(&json)
            .map_err(|e| Error::Term(Box::new(format!("Metadata error: {:?}", e))))?;
        Some(CollectionMetadataUpdate::UpdateMetadata(metadata))
    } else {
        None
    };

    let request = UpdateCollectionRequest::try_new(
        CollectionUuid(collection_uuid),
        new_name,
        parsed_metadata,
        None,
    ).map_err(|e| Error::Term(Box::new(format!("Request error: {:?}", e))))?;

    let mut frontend = bindings.frontend.lock().unwrap();
    let result = bindings.runtime.block_on(async {
        frontend.update_collection(request).await
    });

    match result {
        Ok(collection) => {
            let json = serde_json::to_string(&collection)
                .map_err(|e| Error::Term(Box::new(format!("Serialization error: {:?}", e))))?;
            Ok(json)
        }
        Err(e) => Err(Error::Term(Box::new(format!("{:?}", e)))),
    }
}

rustler::init!("Elixir.ChromEx.Native", load = on_load);
