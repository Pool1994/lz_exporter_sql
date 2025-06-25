import tkinter as tk
import ttkbootstrap as ttk
from ttkbootstrap.constants import *
from tkinter import messagebox
import mysql.connector
import os
import subprocess
import platform


def main():
    try:
        root = ttk.Window(themename="minty")
        root.title("Database Export Tool")
        root.geometry("900x900")
        root.resizable(False, False)
        
        #titulo principal
        title = ttk.Label(root, text="🗃️ Database Export Tool", font=("Helvetica", 20, "bold"),bootstyle="default")
        title.pack(pady=10)
        subtitle = ttk.Label(root, text="Exporta datos, estructura y objetos de base de datos de forma segura entre diferentes servidores", font=("Helvetica", 10),bootstyle="secondary")
        subtitle.pack()
        
        # === Contenedor principal ===
        main_frame = ttk.Frame(root)
        main_frame.pack(pady=20,padx=20,fill="both",expand=True)

        # === Frame izquierdo: Origen ===
        origin_frame = ttk.Labelframe(main_frame,text="📘 Base de Datos Origen",bootstyle="info",padding=10)
        origin_frame.grid(row=0,column=0,padx=10,pady=10,sticky="nsew")
        
        origin_frame.columnconfigure(0, weight=1)
        ttk.Label(origin_frame,text="Host / IP:").grid(row=0,column=0,sticky="w", columnspan=2)
        ttk.Entry(origin_frame).grid(row=1, column=0,columnspan=2, sticky="ew")

        ttk.Label(origin_frame, text="Usuario:").grid(row=2, column=0, sticky="w", columnspan=2)
        ttk.Entry(origin_frame).grid(row=3, column=0,columnspan=2, sticky="w")

        ttk.Label(origin_frame, text="Contraseña:").grid(row=4, column=0, sticky="w", columnspan=2)
        ttk.Entry(origin_frame, show="*").grid(row=5, column=0, columnspan=2, sticky="w")

        ttk.Label(origin_frame, text="Base de Datos:").grid(row=6, column=0, sticky="w", columnspan=2)
        ttk.Entry(origin_frame).grid(row=7, column=0, columnspan=2, sticky="w")
        
        # # === Frame derecho: Destino ===
        destino_frame = ttk.Labelframe(main_frame, text="🟢 Base de Datos Destino",bootstyle="success", padding=10)
        destino_frame.grid(row=0, column=1, padx=10,pady=10, sticky="nsew")
        
        destino_frame.columnconfigure(0, weight=1)
        ttk.Label(destino_frame, text="Host / IP:").grid(row=0, column=0, sticky="w", columnspan=2)
        ttk.Entry(destino_frame).grid(row=1, column=0, columnspan=2, sticky="ew")

        ttk.Label(destino_frame, text="Usuario:").grid(row=2, column=0, sticky="w", columnspan=2)
        ttk.Entry(destino_frame).grid(row=3, column=0, sticky="w")

        ttk.Label(destino_frame, text="Contraseña:").grid(row=4, column=0, sticky="w", columnspan=2)
        ttk.Entry(destino_frame, show="*").grid(row=5, column=0, columnspan=2, sticky="w")

        ttk.Label(destino_frame, text="Base de Datos:").grid(row=6, column=0, sticky="w", columnspan=2)
        ttk.Entry(destino_frame).grid(row=7, column=0, columnspan=2, sticky="w")
        
        # # Ajustar columnas para que se expandan
        main_frame.columnconfigure(0, weight=1)
        main_frame.columnconfigure(1, weight=1)

        # === Frame: Opciones de Exportación ===
        structure_table = tk.BooleanVar(value=True)
        data_table = tk.BooleanVar(value=True)
        stored_procedures = tk.BooleanVar(value=True)
        functions = tk.BooleanVar(value=True)
        triggers = tk.BooleanVar(value=True)
        events = tk.BooleanVar(value=True)
        
        export_options_frame = ttk.Labelframe(
            main_frame,
            text="⚙️ Opciones de Exportación",
            bootstyle="primary",
            padding=10
        )
        export_options_frame.grid(row=1, column=0, columnspan=2, pady=(0, 10), padx=10, sticky="nsew")

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
        ttk.Checkbutton(estructura_frame, text="Estructura de tablas", bootstyle="success",variable=structure_table).pack(anchor="w", pady=2)
        ttk.Checkbutton(estructura_frame, text="Datos de tablas", bootstyle="success",variable=data_table).pack(anchor="w", pady=2)

        # === Columna 2: Objetos de Base de Datos ===
        objetos_frame = ttk.Frame(export_options_frame)
        objetos_frame.grid(row=1, column=1, sticky="nsew", padx=10)

        ttk.Label(objetos_frame, text="⚙️ Objetos de Base de Datos", font=("Helvetica", 10, "bold")).pack(anchor="w", pady=(0, 5))
        ttk.Checkbutton(objetos_frame, text="Stored Procedures",variable=stored_procedures).pack(anchor="w", pady=2)
        ttk.Checkbutton(objetos_frame, text="Functions",variable=functions).pack(anchor="w", pady=2)

        # === Columna 3: Eventos y Triggers ===
        eventos_frame = ttk.Frame(export_options_frame)
        eventos_frame.grid(row=1, column=2, sticky="nsew", padx=10)

        ttk.Label(eventos_frame, text="ℹ️ Eventos y Triggers", font=("Helvetica", 10, "bold")).pack(anchor="w", pady=(0, 5))
        ttk.Checkbutton(eventos_frame, text="Triggers",variable=triggers).pack(anchor="w", pady=2)
        ttk.Checkbutton(eventos_frame, text="Events",variable=events).pack(anchor="w", pady=2)
        
        # Botón: Iniciar Exportación (centrado)
        export_button = ttk.Button(
            main_frame,
            text="🚀 Iniciar Exportación",
            bootstyle="primary",
            width=25,  # ancho opcional
            command=export_selected  # tu función de exportación
        )
        export_button.grid(row=2, column=0, columnspan=3, pady=15)
        root.mainloop()
    except Exception as e:
        print(f"Error creating main window: {e}")
        messagebox.showerror("Error", f"Failed to create main window: {e}")

def export_selected():
    print("Exporting selected items...")
    

if __name__ == "__main__":
    main()