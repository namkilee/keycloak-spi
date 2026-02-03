locals {
  base_defaults = {
    enabled            = false
    runAt              = "03:00"
    windowMinutes      = 3
    batchSize          = 500
    resultType         = "basic"
    httpTimeoutMs      = 5000
    maxConcurrency     = 15
    retryMaxAttempts   = 3
    retryBaseBackoffMs = 250
    taskKeyPrefix      = "userinfosync"
    mappingJson        = jsonencode({ deptId = "response.employees.departmentCode" })
    invalidateOnKeys   = "deptId"
  }

  defaults = merge(
    local.base_defaults,
    var.userinfosync_defaults
  )

  output_userinfosync = merge(
    local.defaults,
    var.userinfosync_overrides
  )
}

output "attributes" {
  value = merge(
    var.extra_realm_attributes,
    {
      "userinfosync.enabled"             = tostring(local.output_userinfosync.enabled)
      "userinfosync.runAt"               = tostring(local.output_userinfosync.runAt)
      "userinfosync.windowMinutes"       = tostring(local.output_userinfosync.windowMinutes)
      "userinfosync.batchSize"           = tostring(local.output_userinfosync.batchSize)
      "userinfosync.resultType"          = tostring(local.output_userinfosync.resultType)
      "userinfosync.httpTimeoutMs"       = tostring(local.output_userinfosync.httpTimeoutMs)
      "userinfosync.maxConcurrency"      = tostring(local.output_userinfosync.maxConcurrency)
      "userinfosync.retry.maxAttempts"   = tostring(local.output_userinfosync.retryMaxAttempts)
      "userinfosync.retry.baseBackoffMs" = tostring(local.output_userinfosync.retryBaseBackoffMs)
      "userinfosync.taskKeyPrefix"       = tostring(local.output_userinfosync.taskKeyPrefix)
      "userinfosync.mappingJson"         = tostring(local.output_userinfosync.mappingJson)
      "userinfosync.invalidateOnKeys"    = tostring(local.output_userinfosync.invalidateOnKeys)
    }
  )
}
