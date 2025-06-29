import os
import mysql.connector
import gc

from config.db_config import DBConfig
from config.export_options import ExportOptions
from datetime import datetime
from typing import List

from exporter.store_procedure_exporter import StoreProcedureExporter
from exporter.trigger_exporter import TriggerExporter
from exporter.event_exporter import EventExporter
from exporter.functions_exporter import FunctionsExporter
from exporter.data_table_exporter import DataTableExporter
from pprint import pprint
from config.progress_callback import ProgressCallback
from helpers.utils import join_file_path, merge_all_files, merge_sql_files,directory_exists
from exporter.export_path import ExportPath


class BaseExporter:
    def __init__(self,db_config:DBConfig, export_options:ExportOptions, output_directory:str,progress_callbacks:ProgressCallback):
        self.db_config = db_config
        self.export_options = export_options
        self.output_directory = output_directory
        self.progress_callbacks = progress_callbacks
    
    def export_all(self):
       
        cnx_origen = mysql.connector.connect(
            host= self.db_config.host,
            user= self.db_config.user,
            password= self.db_config.password,
            database= self.db_config.database
        )
        cursor_origen = cnx_origen.cursor(dictionary=True)
        
        try:
           
            db=self.db_config.database
            
            # Crear directorio de salida
            output_dir = os.path.join("export_sql",f"{db}_{datetime.now().strftime('%Y%m%d_%H%M%S')}")
            os.makedirs(output_dir, exist_ok=True)
        
            filesPaths: List[ExportPath] = []
            total_final = 0
            
            # Seccion 1: Exportar estructura de tablas
            if self.export_options.table_data:
                table_export = DataTableExporter(
                    cursor=cursor_origen, 
                    db_name=db, 
                    base_folder=output_dir,
                    progress_callback= self.progress_callbacks.tables
                )
                result_export = table_export.export()
                total_final += result_export.total
                filesPaths.append(
                    ExportPath(
                        result_export.path_dir,
                        join_file_path(output_dir,'00_tables.sql')
                    )
                )
            # Seccion 2: Exportar objetos almacenados
            if self.export_options.store_procedures:
                storeProcedure = StoreProcedureExporter(
                    cursor=cursor_origen, 
                    dbName=db, 
                    base_folder= output_dir,
                    progress_callback= self.progress_callbacks.procedures
                )
                result_export = storeProcedure.export()
                total_final += result_export.total
                filesPaths.append(
                    ExportPath(
                        result_export.path_dir,
                        join_file_path(output_dir,'00_stored_procedures.sql')
                    )
                )
            # Seccion 3: Exportar disparadores (triggers)
            if self.export_options.triggers:
                triggers = TriggerExporter(
                    cursor=cursor_origen, 
                    dbName=db, 
                    base_folder= output_dir,
                    progress_callback= self.progress_callbacks.triggers
                )
                result_export = triggers.export()
                total_final += result_export.total
                filesPaths.append(
                    ExportPath(
                        result_export.path_dir,
                        join_file_path(output_dir,'00_triggers.sql')
                    )
                )
            # Seccion 4: Exportar eventos
            if self.export_options.events:
                events_exp = EventExporter(
                    cursor=cursor_origen, 
                    db_name=db, 
                    base_folder= output_dir,
                    progress_callback= self.progress_callbacks.events
                )
                result_export = events_exp.export()
                total_final += result_export.total
                filesPaths.append(
                    ExportPath(
                        result_export.path_dir,
                        join_file_path(output_dir,'00_events.sql')
                    )
                )
            # Seccion 5: Exportar funciones
            if self.export_options.functions:
                functions_ex = FunctionsExporter(
                    cursor=cursor_origen, 
                    dbName=db, 
                    base_folder= output_dir,
                    progress_callback= self.progress_callbacks.functions
                )
                result_export = functions_ex.export()
                total_final += result_export.total
                filesPaths.append(
                    ExportPath(
                        result_export.path_dir,
                        join_file_path(output_dir,'00_functions.sql')
                    )
                )
            cnx_origen.close()
            cursor_origen.close()
            gc.collect()
            
            #merge files
            total_directories = sum(
                1 for group in filesPaths
                if directory_exists(group.path)
            )
           
            start_index = 1
            
            for files_group in filesPaths:
                start_index = merge_sql_files(
                    files_group.path,
                    files_group.output_file,
                    self.progress_callbacks.merge_files,
                    total_final,
                    start_index
                )
            
            merge_all_files(
                filesPaths, 
                join_file_path(
                    self.output_directory,
                    f"{self.db_config.database}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.sql"
                ),
                self.progress_callbacks.backup,
                total_directories
            )
        except Exception as e:
            raise e
        finally:
            cnx_origen.close()
            cursor_origen.close()
            gc.collect()
            
        