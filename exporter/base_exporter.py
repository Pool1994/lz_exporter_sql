import os
import pymysql as mysql
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
from helpers.utils import joinFilePath, mergeAllFiles, mergeSqlFiles
from pymysql.cursors import DictCursor
class BaseExporter:
    def __init__(self,db_config:DBConfig, export_options:ExportOptions, output_directory:str,progress_callbacks:ProgressCallback):
        self.db_config = db_config
        self.export_options = export_options
        self.output_directory = output_directory
        self.progress_callbacks = progress_callbacks
    
    def export_all(self):
        conn = mysql.connect(
            host= self.db_config.host,
            user= self.db_config.user,
            password= self.db_config.password,
            database= self.db_config.database
        )
        cursor = conn.cursor(cursor=DictCursor)
        db=self.db_config.database
        
        output_dir = os.path.join("export_sql",f"{db}_{datetime.now().strftime('%Y%m%d_%H%M%S')}")
        os.makedirs(output_dir, exist_ok=True)
        
        filesPaths = [
            joinFilePath(output_dir,'00_tables.sql'),
            joinFilePath(output_dir,'00_stored_procedures.sql'),
            joinFilePath(output_dir,'00_triggers.sql'),
            joinFilePath(output_dir,'00_events.sql'),
            joinFilePath(output_dir,'00_functions.sql'),
        ]
        
        # Seccion 1: Exportar estructura de tablas
        if self.export_options.table_data:
           table_export = DataTableExporter(
               cursor=cursor, 
               dbName=db, 
               base_folder=output_dir,
               progress_callback= self.progress_callbacks.tables
            )
           path_dir = table_export.export_database()
           mergeSqlFiles(path_dir,filesPaths[0])
    
        # Seccion 2: Exportar objetos almacenados
        if self.export_options.store_procedures:
            storeProcedure = StoreProcedureExporter(
                cursor=cursor, 
                dbName=db, 
                base_folder= output_dir,
                progress_callback= self.progress_callbacks.procedures
            )
            path_dir = storeProcedure.export()
            mergeSqlFiles(path_dir,filesPaths[1])
         
        # Seccion 3: Exportar disparadores (triggers)
        if self.export_options.triggers:
            triggers = TriggerExporter(
                cursor=cursor, 
                dbName=db, 
                base_folder= output_dir,
                progress_callback= self.progress_callbacks.triggers
            )
            path_dir = triggers.export()
            mergeSqlFiles(path_dir, filesPaths[2])
           
        # Seccion 4: Exportar eventos
        if self.export_options.events:
            events_exp = EventExporter(
                cursor=cursor, 
                dbName=db, 
                base_folder= output_dir,
                progress_callback= self.progress_callbacks.events
            )
            path_dir = events_exp.export()
            mergeSqlFiles(path_dir, filesPaths[3])
           
        # Seccion 5: Exportar funciones
        if self.export_options.functions:
            functions_ex = FunctionsExporter(
                cursor=cursor, 
                dbName=db, 
                base_folder= output_dir,
                progress_callback= self.progress_callbacks.functions
            )
            path_dir = functions_ex.export()
            mergeSqlFiles(path_dir, filesPaths[4])
            
        #merge files
        mergeAllFiles(filesPaths, joinFilePath(self.output_directory,f"dump_{datetime.now().strftime('%Y%m%d_%H%M%S')}.sql"))
        