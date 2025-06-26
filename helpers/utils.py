
import os
import re

def cleanDefiner(create_stmt:str) -> str:
    """
    Limpia el DEFINER del CREATE y agrega delimitadores para bloque SQL.
    """
    # Eliminar DEFINER usando expresión regular
    stmt_without_definer = re.sub(r"DEFINER=`[^`]+`@`[^`]+`\s+", "", create_stmt)
    
    # Envolver con delimitadores
    final_stmt = f"DELIMITER $$\n\n{stmt_without_definer} $$\n\nDELIMITER ;\n"
    return final_stmt

def saveSqlFile(folder:str,name:str,sql:str) -> str:
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder,f"{name}.sql")
    with open(path, "w", encoding="utf-8") as file:
        file.write(sql+"\n")
    return path

def mergeSqlFiles(directory:str,outputFile:str) -> str:
    
    if not os.path.exists(directory):
        return
    files_merged = 0
    with open(outputFile,'w', encoding="utf-8") as outfile:
        for fileName in sorted(os.listdir(directory)):
            filePath = os.path.join(directory,fileName)
            if os.path.isfile(filePath) and fileName.endswith(".sql"):
                outfile.write(f"-- Archivo: {fileName}\n")
                with open(filePath,'r', encoding="utf-8") as infile:
                    for line in infile:
                        outfile.write(line)
                outfile.write("\n\n") 
                os.remove(filePath)
                files_merged += 1
    if files_merged == 0:
        print(f"[INFO] No se encontraron archivos SQL en '{directory}' para fusionar.")

    # Eliminar directorio si está vacío
    if not os.listdir(directory):
        os.rmdir(directory)

def joinFilePath(directory:str,fileName:str) -> str:
    return os.path.join(directory,fileName)

def mergeAllFiles(files:list[str], destinationFile:str):
    
    header = [
        "START TRANSACTION;",
        "/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;",
        "/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;",
        "/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;",
        "/*!50503 SET NAMES utf8mb4 */;",
        "/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;",
        "/*!40103 SET TIME_ZONE='+00:00' */;",
        "/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;",
        "/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;",
        "/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;",
        "/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;\n"
    ]

    footer = [
        "COMMIT;",
        "/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;",
        "/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;",
        "/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;",
        "/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;",
        "/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;",
        "/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;",
        "/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;",
        "/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;"
    ]
    
    with open(destinationFile,'w',encoding="utf-8") as outfile:
        outfile.write("\n".join(header) + "\n\n")
        for filePath in files:
            if os.path.exists(filePath):
                outfile.write(f"--- Inicio de: {os.path.basename(filePath)} ---\n")
                with open(filePath,'r', encoding="utf-8") as infile:
                    for line in infile:
                        outfile.write(line)
                outfile.write("\n\n")
                # eliminar archivo original
                os.remove(filePath)
            else:
                print(f"[ERROR] Archivo {os.path.basename(filePath)} no existe.")
        outfile.write("\n".join(footer) + "\n\n")
    # Eliminar directorio si está vacío
    folder = os.path.dirname(files[0])
    if os.path.exists(folder) and not os.listdir(folder):
        os.rmdir(folder)