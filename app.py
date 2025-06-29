from ttkbootstrap import  Window
from gui import ExportApp
from screeninfo import get_monitors
def main():
    # Tamaño de la ventana
    ancho_ventana = 800
    alto_ventana = 870
    root = Window(themename="superhero")
    root.geometry(f"{ancho_ventana}x{alto_ventana}")
    monitores = get_monitors()
    
    monitor_laptop = monitores[0]
    
    
    pantalla_ancho = monitor_laptop.width
    pantalla_alto = monitor_laptop.height
    
    #calcular el centro de la ventana
    pos_x = (pantalla_ancho - ancho_ventana) // 2 + monitor_laptop.x
    pos_y = (pantalla_alto - alto_ventana) // 2 + monitor_laptop.y
    root.geometry(f"{ancho_ventana}x{alto_ventana}+{pos_x}+{pos_y}")
    app = ExportApp(root)
    root.mainloop()
   
if __name__ == "__main__":
    main()