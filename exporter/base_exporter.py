import os
import mysql.connector
from config.db_config import DBConfig
from config.export_options import ExportOptions
from datetime import datetime
from exporter.store_procedure_exporter import StoreProcedureExporter
from exporter.trigger_exporter import TriggerExporter
from exporter.event_exporter import EventExporter
from exporter.functions_exporter import FunctionsExporter
from exporter.data_table_exporter import DataTableExporter
from pprint import pprint
from config.progress_callback import ProgressCallback
class BaseExporter:
    def __init__(self,db_config:DBConfig, export_options:ExportOptions, output_directory:str,progress_callbacks:ProgressCallback):
        self.db_config = db_config
        self.export_options = export_options
        self.output_directory = output_directory
        self.progress_callbacks = progress_callbacks
    
    def export_all(self):
        conn = mysql.connector.connect(
            host= self.db_config.host,
            user= self.db_config.user,
            password= self.db_config.password,
            database= self.db_config.database
        )
        cursor = conn.cursor(dictionary=True)
        db=self.db_config.database
        
        output_dir = os.path.join("export_sql",f"{db}_{datetime.now().strftime('%Y%m%d_%H%M%S')}")
        os.makedirs(output_dir, exist_ok=True)
        
        if self.export_options.table_data:
           table_export = DataTableExporter(
               cursor=cursor, 
               dbName=db, 
               base_folder=output_dir,
               progress_callback= self.progress_callbacks.tables
            )
           res = table_export.export_database()
           pprint(f"Tablas encontradas: {res}")
           
        if self.export_options.store_procedures:
            storeProcedure = StoreProcedureExporter(
                cursor=cursor, 
                dbName=db, 
                base_folder= output_dir,
                progress_callback= self.progress_callbacks.procedures
            )
            path_dir = storeProcedure.export()
            print(f"Procedimientos almacenados exportados a: {path_dir}")
        if self.export_options.triggers:
            triggers = TriggerExporter(
                cursor=cursor, 
                dbName=db, 
                base_folder= output_dir,
                progress_callback= self.progress_callbacks.triggers
            )
            path_dir = triggers.export()
            print(f"Triggers exportados a: {path_dir}")
        
        if self.export_options.events:
            events_exp = EventExporter(
                cursor=cursor, 
                dbName=db, 
                base_folder= output_dir,
                progress_callback= self.progress_callbacks.events
            )
            path_dir = events_exp.export()
            print(f"Events exportados a: {path_dir}")
        
        if self.export_options.functions:
            functions_ex = FunctionsExporter(
                cursor=cursor, 
                dbName=db, 
                base_folder= output_dir,
                progress_callback= self.progress_callbacks.functions
            )
            path_dir = functions_ex.export()
            print(f"Functions exportados a: {path_dir}")
        
        
        print(f"Exportación completada. Archivos guardados en: {output_dir}")