# ================================================================================
# Service Bus Namespace + Queue
# Replaces AWS SQS. RBAC-only auth (local_auth_enabled=false).
# Role assignments reference the Function App identity from 02-functions.
# ================================================================================

resource "azurerm_servicebus_namespace" "cartoonify" {
  name                = "sb-cartoonify-${random_id.suffix.hex}"
  location            = azurerm_resource_group.cartoonify.location
  resource_group_name = azurerm_resource_group.cartoonify.name
  sku                 = "Standard"
  local_auth_enabled  = false
}

resource "azurerm_servicebus_queue" "jobs" {
  name         = "cartoonify-jobs"
  namespace_id = azurerm_servicebus_namespace.cartoonify.id

  # lock_duration exceeds the Function App worker timeout so a message cannot
  # be re-delivered while the worker is still processing it
  lock_duration      = "PT3M"
  max_delivery_count = 10

  # TTL matches the 7-day job retention window
  default_message_ttl                  = "P7D"
  dead_lettering_on_message_expiration = true

  max_size_in_megabytes        = 1024
  requires_duplicate_detection = false
  requires_session             = false
}
