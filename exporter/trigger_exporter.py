import os
import gc
from pymysql.cursors import DictCursor
from helpers.utils import cleanDefiner, saveSqlFile

class TriggerExporter:
    def __init__(self,cursor:DictCursor,dbName:str,base_folder:str, progress_callback: tuple[int,int]):
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
        print(f"Total triggers encontrados: {total}")
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
        return self.path_dir