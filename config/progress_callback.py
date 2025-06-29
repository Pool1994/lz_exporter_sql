from dataclasses import dataclass
from typing import Callable, Tuple
@dataclass
class ProgressCallback:
    procedures: Callable[[Tuple[int,int]], None]
    triggers: Callable[[Tuple[int,int]], None]
    events: Callable[[Tuple[int,int]], None]
    functions: Callable[[Tuple[int,int]], None]
    tables: Callable[[Tuple[int,int]], None]
    merge_files: Callable[[Tuple[int,int]], None]
    backup: Callable[[Tuple[int,int]], None]