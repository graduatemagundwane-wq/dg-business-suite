"""Fast Argon2 test parameters; production uses its own strong defaults."""
from argon2 import PasswordHasher
import security
security.hasher = PasswordHasher(time_cost=1, memory_cost=8192, parallelism=1)
