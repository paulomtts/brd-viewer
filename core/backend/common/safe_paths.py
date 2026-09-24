import os


def inside(root_real, path_real):
    return path_real == root_real or path_real.startswith(root_real + os.sep)


def contained_file(root, rel):
    """Real path of a regular file `rel` under `root`, else None."""
    if not os.path.isdir(root):
        return None
    root_real = os.path.realpath(root)
    real = os.path.realpath(os.path.join(root, rel))
    if inside(root_real, real) and os.path.isfile(real):
        return real
    return None
