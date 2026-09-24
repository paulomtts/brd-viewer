import os
import tempfile


def _discard(path):
    try:
        os.unlink(path)
    except OSError:
        pass


def write_atomic(real_path, data, mode=None):
    """Replace (or create) a file atomically. An existing file keeps its mode;
    a new one gets `mode` (default 0o644)."""
    directory = os.path.dirname(real_path)
    existing = os.stat(real_path).st_mode & 0o777 if os.path.exists(real_path) else None
    fd, tmp = tempfile.mkstemp(prefix=".tmp-", dir=directory)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        os.chmod(tmp, existing if existing is not None else (mode if mode is not None else 0o644))
        os.replace(tmp, real_path)
    except BaseException:
        _discard(tmp)
        raise


def write_new(real_path, data, mode=0o644):
    """Create a file that must not exist yet: the content is fully written
    before the name appears, and a concurrent creator of the same name loses
    with FileExistsError instead of being overwritten."""
    directory = os.path.dirname(real_path)
    fd, tmp = tempfile.mkstemp(prefix=".tmp-", dir=directory)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        os.chmod(tmp, mode)
        os.link(tmp, real_path)
    finally:
        _discard(tmp)
