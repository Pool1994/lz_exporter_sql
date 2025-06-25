import ttkbootstrap as ttk
import os
from ttkbootstrap.constants import *
from tkinter import messagebox
from tkinter import filedialog
from exporter.base_exporter import BaseExporter
from config.db_config import DBConfig
from config.export_options import ExportOptions
class ExportApp:
    def __init__(self, root: ttk.Window):
        self.root = root
        self.root.title("Database Export Tool")
        self.root.resizable(False, False)
      
        
        
        self.structure_table_var = ttk.BooleanVar(value=True)
        self.data_table_var = ttk.BooleanVar(value=True)
        self.functions_var = ttk.BooleanVar(value=True)
        self.triggers_var = ttk.BooleanVar(value=True)
        self.events_var = ttk.BooleanVar(value=True)
        self.stored_procedures_var = ttk.BooleanVar(value=True)
        self.output_directory = ttk.StringVar()

        
        self.createWidgets()
    def createWidgets(self):
        title = ttk.Label(self.root, text="🗃️ Database Export Tool", font=("Helvetica", 20, "bold"),bootstyle="default")
        title.pack(pady=10)
        subtitle = ttk.Label(self.root, text="Exporta datos, estructura y objetos de base de datos de forma segura entre diferentes servidores", font=("Helvetica", 10),bootstyle="secondary")
        subtitle.pack()
        
         # === Contenedor principal ===
        main_frame = ttk.Frame(self.root)
        main_frame.pack(pady=20,padx=20,fill="both",expand=True)
        main_frame.columnconfigure(0, weight=1)
        
         # === Frame izquierdo: Origen ===
        origin_frame = ttk.Labelframe(main_frame,text="📘 Base de Datos Origen",bootstyle="info",padding=10)
        origin_frame.grid(row=0,column=0,padx=10,pady=10,sticky="nsew")
        origin_frame.columnconfigure(0, weight=1)
        
        self.origin_host = ttk.Entry(origin_frame)
        self.origin_user = ttk.Entry(origin_frame)
        self.origin_password = ttk.Entry(origin_frame, show="*")
        self.origin_database = ttk.Entry(origin_frame)
        self.export_path = ttk.Entry(origin_frame,textvariable=self.output_directory,state="readonly")
        #ORIgEN HOST
        ttk.Label(origin_frame,text="Host / IP:").grid(row=0,column=0,sticky="w", columnspan=2)
        self.origin_host.grid(row=1, column=0, sticky="ew")
        
        #USER
        ttk.Label(origin_frame, text="Usuario:").grid(row=2, column=0, sticky="w")
        self.origin_user.grid(row=3,column=0,sticky="w")
        
        #PASSWORD
        ttk.Label(origin_frame, text="Contraseña:").grid(row=4, column=0, sticky="w")
        self.origin_password.grid(row=5, column=0, sticky="w")
        
        #DATABASE
        ttk.Label(origin_frame, text="Base de Datos:").grid(row=6, column=0, sticky="w")
        self.origin_database.grid(row=7, column=0, sticky="w")
        
        #PATH
        ttk.Label(origin_frame, text="Ruta de Exportación:").grid(row=8, column=0, sticky="w")
        self.export_path.grid(row=9, column=0, sticky="ew",pady=2)
        ttk.Button(origin_frame,text="Seleccionar", bootstyle="secondary",command=self.selectOutputPath).grid(row=9,column=1,sticky="e",pady=(0, 5))
        # Frame opciones de exportación
        export_options_frame = ttk.Labelframe(
            main_frame,
            text="⚙️ Opciones de Exportación",
            bootstyle="primary",
            padding=10
        )
        export_options_frame.grid(row=1, column=0, columnspan=2, pady=(0, 10), padx=10, sticky="nsew")
        export_options_frame.columnconfigure((0,1,2), weight=1)
        
        # Subtítulo (puede ser solo un Label dentro del Labelframe)
        ttk.Label(
            export_options_frame,
            text="Selecciona qué elementos deseas exportar",
            font=("Helvetica", 9),
            bootstyle="secondary"
        ).grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 10))
        
        # Configurar columnas
        export_options_frame.columnconfigure((0, 1, 2), weight=1)
        
        # === Columna 1: Estructura y Datos ===
        estructura_frame = ttk.Frame(export_options_frame)
        estructura_frame.grid(row=1, column=0, sticky="nsew", padx=10)

        ttk.Label(estructura_frame, text="🗄️ Estructura y Datos", font=("Helvetica", 10, "bold")).pack(anchor="w", pady=(0, 5))
        ttk.Checkbutton(estructura_frame, text="Estructura de tablas", bootstyle="success",variable=self.structure_table_var).pack(anchor="w", pady=2)
        ttk.Checkbutton(estructura_frame, text="Datos de tablas", bootstyle="success",variable=self.data_table_var).pack(anchor="w", pady=2)

        # === Columna 2: Objetos de Base de Datos ===
        objetos_frame = ttk.Frame(export_options_frame)
        objetos_frame.grid(row=1, column=1, sticky="nsew", padx=10)

        ttk.Label(objetos_frame, text="⚙️ Objetos de Base de Datos", font=("Helvetica", 10, "bold")).pack(anchor="w", pady=(0, 5))
        ttk.Checkbutton(objetos_frame, text="Stored Procedures",variable=self.stored_procedures_var).pack(anchor="w", pady=2)
        ttk.Checkbutton(objetos_frame, text="Functions",variable=self.functions_var).pack(anchor="w", pady=2)

        # === Columna 3: Eventos y Triggers ===
        eventos_frame = ttk.Frame(export_options_frame)
        eventos_frame.grid(row=1, column=2, sticky="nsew", padx=10)

        ttk.Label(eventos_frame, text="ℹ️ Eventos y Triggers", font=("Helvetica", 10, "bold")).pack(anchor="w", pady=(0, 5))
        ttk.Checkbutton(eventos_frame, text="Triggers",variable=self.triggers_var).pack(anchor="w", pady=2)
        ttk.Checkbutton(eventos_frame, text="Events",variable=self.events_var).pack(anchor="w", pady=2)  
        
        # Botón: Iniciar Exportación (centrado)
        export_button = ttk.Button(
            main_frame,
            text="🚀 Iniciar Exportación",
            bootstyle="primary",
            width=25,  # ancho opcional
            command=self.export_action  # tu función de exportación
        )
        export_button.grid(row=2, column=0, columnspan=3, pady=15)
    def export_action(self):
        db_config = {
            "host": self.origin_host.get(),
            "user": self.origin_user.get(),
            "password": self.origin_password.get(),
            "database": self.origin_database.get()
        }
        print(f"Exportando con la siguiente configuración: {db_config}")
        
        if not all(db_config.values()):
            messagebox.showerror("Error", "Por favor, completa todos los campos de la base de datos.")
            return
        try:
            print("Exportando...")
            db_config_var = DBConfig(
                host=db_config["host"],
                user=db_config["user"],
                password=db_config["password"],
                database=db_config["database"]
            )
            export_options = ExportOptions(
                store_procedures=self.stored_procedures_var.get(),
                triggers=self.triggers_var.get(),
                events=self.events_var.get(),
                functions=self.functions_var.get()
            )
            
            export_base = BaseExporter(
                db_config=db_config_var,
                export_options= export_options,
                output_directory=self.output_directory.get()
            )
            export_base.export_all()
            messagebox.showinfo("Éxito", "Exportación completada exitosamente.")
        except Exception as e:
            messagebox.showerror("Error", f"Error al exportar: {e}")
            return
    def centerWindow(self, width:int, height:int):
        self.root.withdraw()  # Oculta temporalmente
        self.root.update_idletasks()  # Procesa eventos pendientes

        screen_width = self.root.winfo_screenwidth()
        screen_height = self.root.winfo_screenheight()

        x = (screen_width // 2) - (width // 2)
        y = (screen_height // 2) - (height // 2)

        self.root.geometry(f"{width}x{height}+{x}+{y}")
        self.root.deiconify()  # Muestra la ventana ya centrada
        
    def selectOutputPath(self):
        home_dir = os.path.expanduser("~")
        selectPath = filedialog.askdirectory(initialdir=home_dir, title="Seleccionar Ruta de Exportación")
        if selectPath:
            self.output_directory.set(selectPath)
        else:
            messagebox.showwarning("Advertencia", "No se seleccionó ninguna ruta de exportación.")