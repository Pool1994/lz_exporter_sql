class DatabaseDestino:
    def __init__(self, host:str, user:str, password:str, database:str):
        self.host = host
        self.user = user
        self.password = password
        self.database = database
    
    def __str__(self):
        return f"Host: {self.host}, User: {self.user}, Password: {self.password}, Database: {self.database}"