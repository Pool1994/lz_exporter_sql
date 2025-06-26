from dataclasses import dataclass

@dataclass
class ExportOptions:
    store_procedures: bool
    triggers: bool
    events: bool
    functions: bool
    table_data: bool