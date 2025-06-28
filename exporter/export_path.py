class ExportPath:
    def __init__(self,path_dir:str,output_file:str):
        self.path = path_dir
        self.output_file = output_file
    def __repr__(self):
        return f"ExportPath(path_dir={self.path},output_file={self.output_file})"
    