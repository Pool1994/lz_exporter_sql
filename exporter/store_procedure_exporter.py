import os
import gc
from mysql.connector.cursor import MySQLCursor
from helpers.utils import cleanDefiner, saveSqlFile
class StoreProcedureExporter:
    def __init__(self,cursor:MySQLCursor,dbName:str,base_folder:str,progress_callback:None):
        self.cursor = cursor
        self.dbName = dbName
        self.path_dir = os.path.join(base_folder, "stored_procedures")
        self.progress_callback = progress_callback
    
    def export(self):
        self.cursor.execute(
            "SELECT SPECIFIC_NAME FROM information_schema.routines WHERE ROUTINE_SCHEMA = %s AND ROUTINE_TYPE = 'PROCEDURE'",
            (self.dbName,)
        )
        procedures = self.cursor.fetchall()
        total = len(procedures)
        print(f"Total procedimientos almacenados encontrados: {total}")
        for i,row in enumerate(procedures,start=1):
            name = row['SPECIFIC_NAME']
            try:
                self.cursor.execute(f"SHOW CREATE PROCEDURE `{name}`")
                res = self.cursor.fetchone()
                if res and 'Create Procedure' in res:
                    sql = cleanDefiner(res['Create Procedure'])
                    saveSqlFile(self.path_dir, name, sql)
                    
            except Exception as e:
                print(f"Error al ejecutar SHOW CREATE PROCEDURE para {name}: {e}")
                continue
            if self.progress_callback:
                self.progress_callback((i,total))
        del procedures
        gc.collect()
        return self.path_dir
        