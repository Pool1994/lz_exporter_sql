import mysql.connector

def get_list_database(host,user,password):
        """ Obtiene la lista de bases de datos de la instancia de MySQL """
        try:
            cnx = mysql.connector.connect(
                host=host,
                user=user,
                password=password
            )
            cursor = cnx.cursor()
            cursor.execute("SHOW DATABASES")
            databases = [bd[0] for bd in cursor.fetchall()]
            cursor.close()
            cnx.close()
            return databases
        except mysql.connector.Error as err:
            return [] 