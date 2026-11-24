# Zino Bridge Protocol v1

Connects the **Zino Editor** (server) with the **Zino Bridge** Godot editor plugin (client).
Defined in `addons/zino_runtime/bridge/zino_protocol.gd`; server in `core/zino_bridge_server.gd`;
client in `addons/zino_bridge/`.

## Transport and session
- WebSocket, text frames, one JSON object per frame, max 8 MB.
- Server binds **127.0.0.1** on a random free port when a project is opened.
- Session file `<project>/Cache/zino_bridge_session.json`:
  `{ "protocol": 1, "host": "127.0.0.1", "port": 49672, "token": "<64 hex>", "pid": 1234, "created": "…Z" }`
  It is deleted when the Zino Editor closes the project.
- The plugin polls for the file every 1.5 s while disconnected and reconnects automatically.

## Handshake
1. Client → `{"type":"hello","protocol":1,"token":"…","client":{"name","godotVersion","projectPath"}}`
2. Server → `{"type":"welcome","protocol":1,"server":{"name","version"}}`
   or `{"type":"reject","reason":"…"}` and close.
- Missing/incorrect token or no hello within **5 s** → connection closed. Only one client at a time.

## Messages
- Request (Zino → Godot): `{"type":"request","id":7,"cmd":"MOVE_OBJECT","payload":{…}}`
- Response: `{"type":"response","id":7,"ok":true,"payload":{…}}` or
  `{"type":"response","id":7,"ok":false,"error":{"code":"INVALID_PAYLOAD","message":"…"}}`
- Event (Godot → Zino): `{"type":"event","name":"SELECTION_CHANGED","payload":{…}}`
- Requests time out after 15 s (`TIMEOUT`); disconnects fail pending requests (`DISCONNECTED`).

## Commands
| Command | Payload | Result |
|---|---|---|
| `PING` | `{}` | `{pong, time}` |
| `GET_INFO` | `{}` | `{godotVersion, projectPath, editedScene, zinoScene, entityCount, playing}` |
| `LOAD_SCENE` | `{scene, sceneName?}` | builds `res://Worlds/<sceneName>.tscn`, opens it; `{path, entityCount, nodeCount}` |
| `CREATE_OBJECT` | `{entity}` | `{id, node}` |
| `UPDATE_OBJECT` | `{entity}` | `{id}` |
| `DELETE_OBJECT` | `{ids}` (descendants included) | `{deleted}` |
| `SELECT_OBJECT` | `{ids}` (empty clears) | `{selected}` |
| `MOVE_OBJECT` / `ROTATE_OBJECT` / `SCALE_OBJECT` | `{id, position|rotation|scale: [x,y,z]}` | `{applied}` |
| `SET_TRANSFORM` | `{items:[{id, position, rotation, scale}]}` | `{applied}` |
| `ASSIGN_MATERIAL` | `{id, material:{preset?, color?[4], metallic?, roughness?}}` | `{id}` |
| `IMPORT_ASSET` | `{path}` — relative, must start with `Assets/`, no `..` | `{imported, type}` |
| `SAVE_SCENE` | `{}` | `{path}` |
| `START_PLAYTEST` / `STOP_PLAYTEST` | `{}` | `{playing}` |

Rotations are Euler degrees (Godot YXZ order); positions in metres.

## Events
| Event | Payload |
|---|---|
| `SELECTION_CHANGED` | `{ids}` — selection made in the Godot editor (Zino-initiated selections are not echoed) |
| `TRANSFORM_CHANGED` | `{items:[{id, position, rotation, scale}]}` — nodes moved in the Godot editor (polled at 5 Hz) |
| `PLAYTEST_STATE` | `{playing}` |
| `LOG` | `{message}` |

## Validation and security
Every request is checked by `ZinoProtocol.validate_request` **in the plugin** before execution:
unknown commands → `UNKNOWN_COMMAND`; malformed payloads (bad ids, non-finite numbers, invalid
scenes, unsafe names or paths) → `INVALID_PAYLOAD`. There is no command that runs code or shell
commands. Tokens are compared in constant time.

## Error codes
`UNKNOWN_COMMAND`, `INVALID_PAYLOAD`, `NOT_FOUND`, `FAILED`, `TIMEOUT`, `DISCONNECTED`.
