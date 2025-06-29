import os
import gc
from mysql.connector.abstracts import MySQLCursorAbstract
from exporter.results_exporter import ResultsExporter

class DataTableExporter:
    def __init__(self, cursor: MySQLCursorAbstract, db_name: str, base_folder: str, progress_callback: tuple[int,int]):
        self.cursor = cursor
        self.db_name = db_name
        self.path_dir = os.path.join(base_folder, "tablas")
        os.makedirs(self.path_dir, exist_ok=True)
        self.progress_callback = progress_callback

    def get_table_names(self):
        self.cursor.execute("SHOW FULL TABLES WHERE Table_type = 'BASE TABLE'")
        rows = self.cursor.fetchall()
        if not rows:
            return []
        table_column_key = list(rows[0].keys())[0]
        return [row[table_column_key] for row in rows]

    def get_create_table_names(self, table_name: str):
        self.cursor.execute(f"SHOW CREATE TABLE `{table_name}`")
        res = self.cursor.fetchone()
        if res and 'Create Table' in res:
            return res['Create Table']
        return None

    def escape_value(self, value):
        if value is None:
            return "NULL"
        elif isinstance(value, (int, float)):
            return str(value)
        else:
            val = (
                str(value)
                .encode("unicode_escape")
                .decode("utf-8")
                .replace("'", "''")
            )
            return f"'{val}'"

    def export_table_to_file(self, table_name: str):
        create_stmt = self.get_create_table_names(table_name)
        if not create_stmt:
            print(f"No se pudo obtener la estructura de la tabla: {table_name}")
            return None

        path = os.path.join(self.path_dir, f"{table_name}.sql")
        
        with open(path, "w", encoding="utf-8") as f:
           
            # Escribir estructura de tabla
            f.write(f"-- \n-- Table structure for table `{table_name}`\n-- \n\n")
            f.write(f"DROP TABLE IF EXISTS `{table_name}`;\n")
            f.write("/*!40101 SET @saved_cs_client     = @@character_set_client */;\n")
            f.write("/*!50503 SET character_set_client = utf8mb4 */;\n")
            f.write(f"{create_stmt};\n")
            f.write("/*!40101 SET character_set_client = @saved_cs_client */;\n\n")

            # Escribir datos
            self.cursor.execute(f"SELECT * FROM `{table_name}`")
            rows = self.cursor.fetchall()
            if not rows:
                return

            cols_names = [f"`{col}`" for col in rows[0].keys()]
            f.write(f"-- \n-- Dumping data for table `{table_name}`\n-- \n\n")
            f.write(f"LOCK TABLES `{table_name}` WRITE;\n")
            f.write(f"/*!40000 ALTER TABLE `{table_name}` DISABLE KEYS */;\n")

            insert_prefix = f"INSERT INTO `{table_name}` ({', '.join(cols_names)}) VALUES\n"
            batch_size = 10
            values_buffer = []

            for i, row in enumerate(rows):
                row_values = [self.escape_value(row[col]) for col in row]
                values_buffer.append(f"({', '.join(row_values)})")

                # Cada batch o última línea
                is_last = i == len(rows) - 1
                if len(values_buffer) == batch_size or is_last:
                    f.write(insert_prefix + ",\n".join(values_buffer) + ";\n")
                    values_buffer.clear()

            f.write(f"/*!40000 ALTER TABLE `{table_name}` ENABLE KEYS */;\n")
            f.write("UNLOCK TABLES;\n")
            del rows
            del cols_names
            gc.collect()

        # # Ejecutar comandos en la base de destino
        # execute_sql_file(path,self.access_db_destino)
        return create_stmt

    def export(self):
        table_names = self.get_table_names()
        total = len(table_names)
        
        # cursor_destino.execute("SET FOREIGN_KEY_CHECKS = 0;")
        for i,table in enumerate(table_names, start=1):
            self.export_table_to_file(table)
            gc.collect()
            
            if self.progress_callback:
                self.progress_callback((i, total))
        # cursor_destino.execute("SET FOREIGN_KEY_CHECKS = 1;")
        return ResultsExporter(total,self.path_dir)
