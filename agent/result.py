"""Result type for flat error handling (like Rust's Result<T, E>)."""

from dataclasses import dataclass
from typing import TypeVar

T = TypeVar("T")


@dataclass
class Ok[T]:
    """Success result."""

    value: T


@dataclass
class Err:
    """Error result."""

    error: str


Result = Ok[T] | Err
