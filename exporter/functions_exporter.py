import os
import gc
from helpers.utils import cleanDefiner, saveSqlFile
from mysql.connector.abstracts import MySQLCursorAbstract
from exporter.results_exporter import ResultsExporter

class FunctionsExporter:
    def __init__(self,cursor:MySQLCursorAbstract,dbName:str,base_folder:str, progress_callback:tuple[int,int]):
        self.cursor = cursor
        self.dbName = dbName
        self.path_dir = os.path.join(base_folder, "functions")
        self.progress_callback = progress_callback
    def export(self):
        self.cursor.execute(
            "SELECT SPECIFIC_NAME FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = %s AND ROUTINE_TYPE = 'FUNCTION'",
            (self.dbName,)
        )
        functions = self.cursor.fetchall()
        total = len(functions)
        for i,row in enumerate(functions,start=1):
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
            if self.progress_callback:
                self.progress_callback((i,total))
        del functions
        gc.collect()
        return ResultsExporter(total,self.path_dir)