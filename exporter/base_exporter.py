import os
import mysql.connector
from config.db_config import DBConfig
from config.export_options import ExportOptions
from datetime import datetime

class BaseExporter:
    def __init__(self,db_config:DBConfig, export_options:ExportOptions, output_directory:str):
        self.db_config = db_config
        self.export_options = export_options
        self.output_directory = output_directory
    
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
        
        