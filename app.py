from ttkbootstrap import  Window
from gui import ExportApp

def main():
    root = Window(themename="minty")
    app = ExportApp(root)
    root.mainloop()

if __name__ == "__main__":
    main()