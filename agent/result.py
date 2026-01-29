"""Result type for flat error handling (like Rust's Result<T, E>)."""

from dataclasses import dataclass


@dataclass
class Ok[T]:
    """Success result."""

    value: T


@dataclass
class Err:
    """Error result."""

    error: str


type Result[T] = Ok[T] | Err
