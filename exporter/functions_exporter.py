import os
from mysql.connector.cursor import MySQLCursor
from helpers.utils import cleanDefiner, saveSqlFile

class FunctionsExporter:
    def __init__(self,cursor:MySQLCursor,dbName:str,base_folder:str):
        self.cursor = cursor
        self.dbName = dbName
        self.path_dir = os.path.join(base_folder, "functions")
    
    def export(self):
        self.cursor.execute(
            "SELECT SPECIFIC_NAME FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = %s AND ROUTINE_TYPE = 'FUNCTION'",
            (self.dbName,)
        )
        
        for row in self.cursor.fetchall():
            name = row['SPECIFIC_NAME']
            try:
                self.cursor.execute(f"SHOW CREATE FUNCTION `{name}`")
                res = self.cursor.fetchone()
                if res and 'Create Function' in res:
                    sql = cleanDefiner(res['Create Function'])
                    saveSqlFile(self.path_dir, name, sql)
            except Exception as e:
                print(f"Error al ejecutar SHOW CREATE FUNCTION para {name}: {e}")
                continue
        return self.path_dir