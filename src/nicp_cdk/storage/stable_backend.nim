## Public facade for the generic stable-memory backend abstraction.
##
## Consumers should import this module (or `storage/memory_manager`) instead of
## reaching into `storage/libs` directly.

import ./libs/stable_backend
import ./libs/ic_stable_backend

export stable_backend
export ic_stable_backend
