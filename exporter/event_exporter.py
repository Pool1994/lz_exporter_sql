import os
from mysql.connector.cursor import MySQLCursor
from helpers.utils import cleanDefiner, saveSqlFile

class EventExporter:
    def __init__(self,cursor:MySQLCursor,dbName:str,base_folder:str):
        self.cursor = cursor
        self.dbName = dbName
        self.path_dir = os.path.join(base_folder, "events")
    
    def export(self):
        self.cursor.execute(
            "SELECT EVENT_NAME FROM information_schema.EVENTS WHERE EVENT_SCHEMA = %s",
            (self.dbName,)
        )
        
        for row in self.cursor.fetchall():
            name = row['EVENT_NAME']
            try:
                self.cursor.execute(f"SHOW CREATE EVENT `{name}`")
                res = self.cursor.fetchone()
                if res and 'Create Event' in res:
                    sql = cleanDefiner(res['Create Event'])
                    print(f"Exportando evento: {name}")
                    saveSqlFile(self.path_dir, name, sql)
            except Exception as e:
                print(f"Error al ejecutar SHOW CREATE EVENT para {name}: {e}")
                continue
        return self.path_dir