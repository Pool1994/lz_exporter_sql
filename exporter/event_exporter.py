import os
import gc
from helpers.utils import cleanDefiner, saveSqlFile
from mysql.connector.abstracts import MySQLCursorAbstract
from results_exporter import ResultsExporter
class EventExporter:
    def __init__(self,cursor:MySQLCursorAbstract,dbName:str,base_folder:str, progress_callback:tuple[int,int]):
        self.cursor = cursor
        self.dbName = dbName
        self.path_dir = os.path.join(base_folder, "events")
        self.progress_callback = progress_callback
    
    def export(self):
        self.cursor.execute(
            "SELECT EVENT_NAME FROM information_schema.EVENTS WHERE EVENT_SCHEMA = %s",
            (self.dbName,)
        )
        
        events = self.cursor.fetchall()
        total = len(events)
        
        for i,row in enumerate(events,start=1):
            name = row['EVENT_NAME']
            try:
                self.cursor.execute(f"SHOW CREATE EVENT `{name}`")
                res = self.cursor.fetchone()
                if res and 'Create Event' in res:
                    sql = cleanDefiner(res['Create Event'])
                    print(f"Exportando evento: {name}")
                    saveSqlFile(self.path_dir, name, sql)
            except Exception as e:
                continue
            if self.progress_callback:
                self.progress_callback((i, total))
        del events
        gc.collect()
        return ResultsExporter(total,self.path_dir)