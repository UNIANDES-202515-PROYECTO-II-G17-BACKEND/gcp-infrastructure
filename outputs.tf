output "gateway_default_hostname" { value = google_api_gateway_gateway.gw.default_hostname }

output "service_uris" {
  value = { for k, v in google_cloud_run_v2_service.svc : k => v.uri }
}

output "redis_host" { value = google_redis_instance.redis.host }

output "cloudsql_instance" { value = google_sql_database_instance.pg.connection_name }

output "dbs" {
  value = { for k, v in google_sql_database.db : k => v.name }
}
