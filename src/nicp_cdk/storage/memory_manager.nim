## Public facade for the `MGR` MemoryManager and the backend-backed
## `StableMemoryView` adapter.
##
## Consumers should import this module instead of `storage/libs/memory_manager`.

import ./libs/stable_backend
import ./libs/ic_stable_backend
import ./libs/memory_manager
import ./libs/memory_view

export stable_backend
export ic_stable_backend
export memory_manager
export memory_view
