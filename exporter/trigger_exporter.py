import os
from mysql.connector.cursor import MySQLCursor
from helpers.utils import cleanDefiner, saveSqlFile

class TriggerExporter:
    def __init__(self,cursor:MySQLCursor,dbName:str,base_folder:str):
        self.cursor = cursor
        self.dbName = dbName
        self.path_dir = os.path.join(base_folder, "triggers")
    
    def export(self):
        self.cursor.execute(
            "SELECT TRIGGER_NAME FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = %s",
            (self.dbName,)
        )
        
        for row in self.cursor.fetchall():
            name = row['TRIGGER_NAME']
            try:
                self.cursor.execute(f"SHOW CREATE TRIGGER `{name}`")
                res = self.cursor.fetchone()
                if res and 'SQL Original Statement' in res:
                    sql = cleanDefiner(res['SQL Original Statement'])
                    saveSqlFile(self.path_dir, name, sql)
            except Exception as e:
                print(f"Error al ejecutar SHOW CREATE TRIGGER para {name}: {e}")
                continue
        return self.path_dir