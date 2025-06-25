from dataclasses import dataclass

@dataclass
class DBConfig:
    host:str
    user:str
    password:str
    database:str 