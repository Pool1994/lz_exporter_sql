
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