
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
        print(f"Directory {directory} does not exist")
        return
    files_merged = 0
    with open(outputFile,'w', encoding="utf-8") as file:
        for fileName in sorted(os.listdir(directory)):
            filePath = os.path.join(directory,fileName)
            if os.path.isfile(filePath) and fileName.endswith(".sql"):
                with open(filePath,'r', encoding="utf-8") as infile:
                    file.write(f"-- Archivo: {fileName}\n")
                    file.write(infile.read())
                    file.write("\n\n")
                os.remove(filePath)
                files_merged += 1
    if files_merged == 0:
        print(f"[INFO] No se encontraron archivos SQL en '{directory}' para fusionar.")
    else:
        print(f"[OK] {files_merged} archivo(s) SQL fusionado(s) en '{outputFile}'. Los archivos originales fueron eliminados.")
    
    # Eliminar directorio si está vacío
    if not os.listdir(directory):
        os.rmdir(directory)
        print(f"[LIMPIEZA] Directorio vacío eliminado: {directory}")
def joinFilePath(directory:str,fileName:str) -> str:
    return os.path.join(directory,fileName)

def mergeAllFiles(files:list[str], destinationFile:str):
    with open(destinationFile,'w',encoding="utf-8") as outfile:
        for filePath in files:
            if os.path.exists(filePath):
                with open(filePath,'r', encoding="utf-8") as infile:
                    outfile.write(f"--- Inicio de: {os.path.basename(filePath)} ---\n")
                    outfile.write(infile.read())
                    outfile.write("\n\n")
                # eliminar archivo original
                os.remove(filePath)
                print(f"[FINAL] Archivo {os.path.basename(filePath)} fusionado exitosamente.")
            else:
                print(f"[ERROR] Archivo {os.path.basename(filePath)} no existe.")
                
        print(f"[FINAL] Archivo combinado creado en: {destinationFile}")
    
    # Eliminar directorio si está vacío
    folder = os.path.dirname(files[0])
    if os.path.exists(folder) and not os.listdir(folder):
        os.rmdir(folder)
        print(f"[LIMPIEZA] Directorio vacío eliminado: {folder}")