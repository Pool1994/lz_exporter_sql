import os
class StoreProcedureExporter:
    def __init__(self,cursor,db,base_folder,clean_definer, save_sql_file):
        self.cursor = cursor
        self.db = db
        self.base_folder = base_folder
        self.clean_definer = clean_definer
        self.save_sql_file = save_sql_file
        
    def export(self):
        os.mkdir(self.base_folder, exist_ok=True)
        self.cursor.execute()
        