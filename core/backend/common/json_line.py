import json


def emit(payload, code=0):
    print(json.dumps(payload))
    return code
