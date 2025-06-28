import os
import gc
from helpers.utils import cleanDefiner, saveSqlFile
from mysql.connector.abstracts import MySQLCursorAbstract
from exporter.results_exporter import ResultsExporter

class TriggerExporter:
    def __init__(self,cursor:MySQLCursorAbstract,dbName:str,base_folder:str, progress_callback: tuple[int,int]):
        self.cursor = cursor
        self.dbName = dbName
        self.path_dir = os.path.join(base_folder, "triggers")
        self.progress_callback = progress_callback
    
    def export(self):
        self.cursor.execute(
            "SELECT TRIGGER_NAME FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = %s",
            (self.dbName,)
        )
        triggers = self.cursor.fetchall()
        total = len(triggers)
        for i,row in enumerate(triggers,start=1):
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
            if self.progress_callback:
                self.progress_callback((i,total))
        del triggers
        gc.collect()
        return ResultsExporter(total,self.path_dir)