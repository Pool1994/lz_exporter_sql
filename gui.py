import threading
import ttkbootstrap as ttk
import os
import time
from ttkbootstrap.constants import *
from tkinter import messagebox
from tkinter import filedialog
from exporter.base_exporter import BaseExporter
from config.db_config import DBConfig
from config.export_options import ExportOptions
from config.progress_callback import ProgressCallback
from exporter.list_databases import get_list_database
from ttkbootstrap.widgets import Entry
from exporter.database_destino import DatabaseDestino

class ExportApp:
    def __init__(self, root: ttk.Window):
        self.root = root
        self.root.protocol("WM_DELETE_WINDOW", self.on_closing)  # Manejar cierre de ventana
        self.root.title("Database Export Tool")
        self.root.resizable(False, False)
        self.progress_bars = {}
        
        
        self.structure_table_var = ttk.BooleanVar(value=True)
        self.data_table_var = ttk.BooleanVar(value=True)
        self.functions_var = ttk.BooleanVar(value=True)
        self.triggers_var = ttk.BooleanVar(value=True)
        self.events_var = ttk.BooleanVar(value=True)
        self.stored_procedures_var = ttk.BooleanVar(value=True)
        self.output_directory = ttk.StringVar()
        
        self.host = ttk.StringVar()
        self.user = ttk.StringVar()
        self.password = ttk.StringVar()
        self.database = ttk.StringVar()
        
        self.host_destino = ttk.StringVar()
        self.user_destino = ttk.StringVar()
        self.password_destino = ttk.StringVar()
        self.database_destino = ttk.StringVar()
        
        self.host_destino_entry: Entry
        self.user_destino_entry: Entry
        self.password_destino_entry: Entry
        self.database_destino_entry: Entry

        self.start_time = None
        self.elapsed_time_label = None
        self.start_time_temp = None
        
        self.create_widgets()
    def create_widgets(self):
        style = ttk.Style()
        title = ttk.Label(self.root, text="🗃️ Herramienta de Exportación de Bases de Datos", font=("Helvetica", 20, "bold"),bootstyle="default")
        title.pack(pady=10)
        subtitle = ttk.Label(self.root, text="Exporta tablas, funciones y objetos de tu base de datos MySQL", font=("Helvetica", 10),bootstyle="secondary")
        subtitle.pack()
        
        # === Contenedor principal ===
        main_frame = ttk.Frame(self.root)
        main_frame.pack(pady=20,padx=20,fill="both",expand=True)
        
        
        # === Frame izquierdo: Origen ===
        origin_frame = ttk.Labelframe(main_frame,text="📘Conexión Origen",bootstyle="info",padding=10)
        origin_frame.grid(row=0,column=0,padx=10,pady=10,sticky="nsew")
        origin_frame.columnconfigure(0, weight=1)
      
        
        style.map("TCombobox", selectbackground=[('readonly', 'fieldbackground')])  # El fondo del texto seleccionado será blanco)
        self.origin_host = ttk.Entry(origin_frame,textvariable=self.host, )
        self.origin_user = ttk.Entry(origin_frame, textvariable= self.user)
        self.origin_password = ttk.Entry(origin_frame, show="*", textvariable=self.password)
        self.origin_database = ttk.Combobox(origin_frame, textvariable= self.database,state="readonly")
        self.export_path = ttk.Entry(origin_frame,textvariable=self.output_directory,state="readonly")
        
        #ORIgEN HOST
        ttk.Label(origin_frame,text="Servidor (Host/IP):",font=("Helvetica","9","bold")).grid(row=0,column=0,sticky="w", columnspan=2,)
        self.origin_host.grid(row=1, column=0, sticky="ew", pady=(0,8))
        
        #USER
        ttk.Label(origin_frame, text="Usuario de MySQL:",font=("Helvetica","9","bold")).grid(row=2, column=0, sticky="w")
        self.origin_user.grid(row=3,column=0,sticky="w", pady=(0,8))
        
        #PASSWORD
        ttk.Label(origin_frame, text="Contraseña de MySQL:", font=("Helvetica","9","bold")).grid(row=4, column=0, sticky="w")
        self.origin_password.grid(row=5, column=0, sticky="w", pady=(0,8))
        
        #DATABASE
        ttk.Label(origin_frame, text="Nombre de la Base de Datos:", font=("Helvetica","9","bold")).grid(row=6, column=0, sticky="w")
        self.origin_database.grid(row=7, column=0, sticky="w", pady=(0,8))
        
        #PATH
        ttk.Label(origin_frame, text="Carpeta de destino para la exportación:", font=("Helvetica","9","bold")).grid(row=8, column=0, sticky="w")
        self.export_path.grid(row=9, column=0, sticky="ew",pady=2)
        ttk.Button(origin_frame,text="Elegir Carpeta", bootstyle="secondary",command=self.select_output_path).grid(row=9,column=0,sticky="e",pady=(0, 5))
        
        #configurar los enventos para actualizar la lista de bases de datos
        self.host.trace_add("write",lambda *args: self.update_combobox_database())
        self.user.trace_add("write",lambda *args: self.update_combobox_database())
        self.password.trace_add("write",lambda *args: self.update_combobox_database())
        
        #FIN FRAME ORIGEN
        
        # # === Frame derecho: Destino ===
        # destino_frame = ttk.Labelframe(main_frame,text="📘 Conexión Destino",bootstyle="info",padding=10)
        # destino_frame.grid(row=0,column=1,padx=10,pady=10,sticky="nsew")
        # destino_frame.columnconfigure(0, weight=1)
        
        # ttk.Label(destino_frame,text="Servidor (Host/IP):",font=("Helvetica","9","bold")).grid(row=0,column=0,sticky="w", columnspan=2,)
        # self.host_destino_entry = Entry(destino_frame,textvariable=self.host_destino)
        # self.host_destino_entry.grid(row=1, column=0, sticky="ew", pady=(0,8))
        
        # ttk.Label(destino_frame, text="Usuario de MySQL:",font=("Helvetica","9","bold")).grid(row=2, column=0, sticky="w")
        # self.user_destino_entry = Entry(destino_frame, textvariable= self.user_destino)
        # self.user_destino_entry.grid(row=3,column=0,sticky="w", pady=(0,8))
        
        # ttk.Label(destino_frame, text="Contraseña de MySQL:", font=("Helvetica","9","bold")).grid(row=4, column=0, sticky="w")
        # self.password_destino_entry = Entry(destino_frame, show="*", textvariable=self.password_destino)
        # self.password_destino_entry.grid(row=5, column=0, sticky="w", pady=(0,8))
        
        # ttk.Label(destino_frame, text="Nombre de la Base de Datos:", font=("Helvetica","9","bold")).grid(row=6, column=0, sticky="w")
        # self.database_destino_entry = Entry(destino_frame, textvariable= self.database_destino)
        # self.database_destino_entry.grid(row=7, column=0, sticky="w", pady=(0,8))

        
        main_frame.columnconfigure(0, weight=1,uniform="equal")
        # main_frame.columnconfigure(1, weight=1,uniform="equal")
    
        # Frame opciones de exportación
        export_options_frame = ttk.Labelframe(
            main_frame,
            text="⚙️ Qué deseas exportar?",
            bootstyle="info",
            padding=10
        )
        export_options_frame.grid(row=1, column=0, columnspan=2, pady=(0, 10), padx=10, sticky="nsew")
        export_options_frame.columnconfigure((0,1,2), weight=1)
        
        # Subtítulo (puede ser solo un Label dentro del Labelframe)
        ttk.Label(
            export_options_frame,
            text="Selecciona los elementos a incluir en la exportación",
            font=("Helvetica", 9),
            bootstyle="secondary"
        ).grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 10))
        
        # Configurar columnas
        export_options_frame.columnconfigure((0, 1, 2), weight=1)
        
        # === Columna 1: Estructura y Datos ===
        estructura_frame = ttk.Frame(export_options_frame)
        estructura_frame.grid(row=1, column=0, sticky="nsew", padx=10)

        ttk.Label(estructura_frame, text="🗄️ Estructura y Datos", font=("Helvetica", 10, "bold")).pack(anchor="w", pady=(0, 5))
        ttk.Checkbutton(estructura_frame, text="Solo estructura de tablas",variable=self.data_table_var).pack(anchor="w", pady=2)
        ttk.Checkbutton(estructura_frame, text="Solo datos de tablas",variable=self.data_table_var).pack(anchor="w", pady=2)

        # === Columna 2: Objetos de Base de Datos ===
        objetos_frame = ttk.Frame(export_options_frame)
        objetos_frame.grid(row=1, column=1, sticky="nsew", padx=10)

        ttk.Label(objetos_frame, text="⚙️ Objetos de Base de Datos", font=("Helvetica", 10, "bold")).pack(anchor="w", pady=(0, 5))
        ttk.Checkbutton(objetos_frame, text="Procedimientos Almacenados",variable=self.stored_procedures_var).pack(anchor="w", pady=2)
        ttk.Checkbutton(objetos_frame, text="Funciones",variable=self.functions_var).pack(anchor="w", pady=2)

        # === Columna 3: Eventos y Triggers ===
        eventos_frame = ttk.Frame(export_options_frame)
        eventos_frame.grid(row=1, column=2, sticky="nsew", padx=10)

        ttk.Label(eventos_frame, text="ℹ️ Eventos y Triggers", font=("Helvetica", 10, "bold")).pack(anchor="w", pady=(0, 5))
        ttk.Checkbutton(eventos_frame, text="Disparadores (Triggers)",variable=self.triggers_var).pack(anchor="w", pady=2)
        ttk.Checkbutton(eventos_frame, text="Eventos",variable=self.events_var).pack(anchor="w", pady=2)  
        
        # Botón: Iniciar Exportación (centrado)
        export_button = ttk.Button(
            main_frame,
            text="🚀 Iniciar Exportación",
            bootstyle="primary",
            command=self.export_action,  # tu función de exportación
            default="disabled"
        )
        export_button.grid(row=2, column=0, columnspan=3, pady=15)
        
        # stop_button = ttk.Button(
        #     main_frame,
        #     text="🛑 Stop",
        #     bootstyle="primary",
        #     command=self.stop_export,
        # )
        # stop_button.grid(row=2, column=1, columnspan=3)
        
        # Progreso de Exportación
        progress_fram = ttk.Labelframe(
            main_frame,
            text="📊 Estado del Proceso de Exportación",
            bootstyle="info",
            padding=10
        )
        progress_fram.grid(row=3, column=0, columnspan=2, pady=(0, 10), padx=10, sticky="nsew")
        progress_fram.columnconfigure((0,1,2), weight=1)
        
        progress_sections = [
            ("Tablas","data_table"),
            ("Procedimientos almacenados","procedures"),
            ("(Disparadores) Triggers","triggers"),
            ("Eventos","events"),
            ("Funciones","functions"),
            ("fusión de Archivos","merge_files"),
            ("Copia de seguridad","backup"),
        ]
        
        for idx, (label_text,key) in enumerate(progress_sections):
            label = ttk.Label(progress_fram,text=label_text, font=("Helvetica",9))
            label.grid(row=3+idx,column=0,sticky="w", padx=(10,0))
            
            progress = ttk.Progressbar(
                progress_fram,
                orient="horizontal",
                length=300,
                mode="determinate",
            )
            progress.grid(row=3+idx,column=1, columnspan=2,padx=10,sticky="ew")
            self.progress_bars[key] = {
                "bar": progress,
                "label": ttk.Label(progress_fram, text="0%")
            }
            self.progress_bars[key]["label"].grid(row=3+idx, column=3, padx=(5, 0))
        
        self.elapsed_time_label = ttk.Label(progress_fram, text="Tiempo transcurrido: 0s", font=("Helvetica", 9, "italic"))
        self.elapsed_time_label.grid(row=10, column=0, columnspan=4, sticky="w", padx=10, pady=(10, 0))
    def export_action(self):
        db_config = {
            "host": self.host.get(),
            "user": self.user.get(),
            "password": self.password.get(),
            "database": self.database.get()
        }
        
        db_config_destino = {
            "host": self.host_destino.get(),
            "user": self.user_destino.get(),
            "password": self.password_destino.get(),
            "database": self.database_destino.get()
        }
        
        if not all(db_config.values()):
            messagebox.showerror("Error", "Faltan datos de conexión Origen. Completa todos los campos.")
            return
        
        # if not all(db_config_destino.values()):
        #     messagebox.showerror("Error", "Faltan datos de conexión Destino. Completa todos los campos.")
        #     return
        
        if not self.export_path.get():
            messagebox.showwarning("Advertencia", "No seleccionaste una carpeta de destino")
            return
        try:
            self.start_time = time.time()
            self.start_time_temp = self.start_time
            self.update_timer()
            
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
                functions=self.functions_var.get(),
                table_data= self.data_table_var.get()
            )
            
            progressCallbacks = ProgressCallback(
                procedures=lambda val: self.update_progress("procedures", val),
                triggers=lambda val: self.update_progress("triggers", val),
                events=lambda val: self.update_progress("events", val),
                functions=lambda val: self.update_progress("functions", val),
                tables=lambda val: self.update_progress("data_table", val),
                merge_files=lambda val: self.update_progress("merge_files", val),
                backup=lambda val: self.update_progress("backup", val)
            )
            self.set_widgets_state("disabled")  # Deshabilitar widgets durante la exportación
            def runExport():
                try:
                    self.update_progress("data_table", (0,0))
                    self.update_progress("procedures", (0,0))
                    self.update_progress("triggers", (0,0))
                    self.update_progress("events", (0,0))
                    self.update_progress("functions", (0,0))
                    self.update_progress("merge_files", (0,0))
                    self.update_progress("backup", (0,0))
                    
                    export_base = BaseExporter(
                        db_config=db_config_var,
                        export_options= export_options,
                        output_directory=self.output_directory.get(),
                        progress_callbacks=progressCallbacks
                    )
                    
                    database_destino = DatabaseDestino(
                        host=self.host_destino.get(),
                        user=self.user_destino.get(),
                        password=self.password_destino.get(),
                        database=self.database_destino.get()
                    )
                    
                    export_base.export_all()
                     # Mostrar mensaje final en el hilo principal
                    self.root.after(0, lambda: [
                        self.stop_time(),
                        self.set_widgets_state("normal"),  # Habilitar widgets nuevamente,
                        self.export_path.config(state="readonly"),
                        self.origin_database.config(state="readonly"),
                        messagebox.showinfo("Éxito", "Exportación completada exitosamente.")
                    ])
                except Exception as e:
                    error_msg = str(e)
                    print(f"Error al exportar: {error_msg}")
                    self.root.after(0, lambda: [
                        self.stop_time(),
                        self.set_widgets_state("normal"),  # Habilitar widgets nuevamente
                        self.export_path.config(state="readonly"),
                        self.origin_database.config(state="readonly"),
                        messagebox.showerror("Error", f"Error al exportar: {error_msg}")
                    ])
            threading.Thread(target=runExport).start()
            
        except Exception as e:
            self.stop_time(),
            self.set_widgets_state("normal")  # Habilitar widgets nuevamente,
            self.export_path.config(state="readonly"),
            self.origin_database.config(state="readonly"),
            messagebox.showerror("Error", f"Error al exportar: {e}")
            print(f"Error al exportar: {e}")
            return
    def center_window(self, width:int, height:int):
        self.root.withdraw()  # Oculta temporalmente
        self.root.update_idletasks()  # Procesa eventos pendientes

        screen_width = self.root.winfo_screenwidth()
        screen_height = self.root.winfo_screenheight()

        x = (screen_width // 2) - (width // 2)
        y = (screen_height // 2) - (height // 2)

        self.root.geometry(f"{width}x{height}+{x}+{y}")
        self.root.deiconify()  # Muestra la ventana ya centrada
        
    def select_output_path(self):
        home_dir = os.path.expanduser("~")
        selectPath = filedialog.askdirectory(initialdir=home_dir, title="Seleccionar Ruta de Exportación")
        if selectPath:
            self.output_directory.set(selectPath)
        
    def update_progress(self, key: str, value: tuple):
        if key in self.progress_bars:
            current, total = value
            percentage = (current / total * 100) if total else 0
            self.progress_bars[key]["bar"]["value"] = percentage
            self.progress_bars[key]["label"].config(text=f"{percentage:.2f}%")
            self.progress_bars[key]["bar"].update_idletasks()
    
    def update_timer(self):
        if self.start_time is None:
            return  # Detener temporizador si ya se completó

        elapsed = int(time.time() - self.start_time)
        hrs, rem = divmod(elapsed, 3600)
        mins, secs = divmod(rem, 60)
        tiempo_formateado = f"{hrs:02}:{mins:02}:{secs:02}"

        self.elapsed_time_label.config(text=f"Tiempo transcurrido: {tiempo_formateado}")
        self.root.after(1000, self.update_timer)  # Actualizar cada segundo
    
    def stop_time(self):
        final_elapsed = int(time.time() - self.start_time_temp)
        hrs, rem = divmod(final_elapsed, 3600)
        mins, secs = divmod(rem, 60)
        tiempo_final = f"{hrs:02}:{mins:02}:{secs:02}"
        self.elapsed_time_label.config(text=f"Tiempo Total: {tiempo_final}")

        self.start_time = None  # Detener temporizador
        
    def set_widgets_state(self,state:str):
        for child in self.root.winfo_children():
            self._set_state_recursive(child,state)

    def _set_state_recursive(self,widget,state):
        try:
            widget.configure(state=state)
        except Exception as e:
            # Algunos widgets no tienen el método configure, como Frame o Label
            pass
        for child in widget.winfo_children():
            self._set_state_recursive(child, state)
    def on_closing(self):
        if self.start_time is not None:
            messagebox.showwarning("Exportación en curso", "Espera a que finalice para cerrar la aplicación.")
        else:
            self.root.destroy()
    
    def stop_export(self):
        self.start_time = None
        self.set_widgets_state("normal")
    
    def update_combobox_database(self):
        
        host = self.host.get()
        user = self.user.get()
        password = self.password.get()
        
        if(host and user and password):
            bases = get_list_database(host,user,password)
            self.origin_database["values"] = bases
        else:
            # Si algino de los campos no estan completos, limpiar la lista de bases de datos
            self.origin_database["values"] = []
            