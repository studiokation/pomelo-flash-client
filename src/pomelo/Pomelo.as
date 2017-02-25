package pomelo {

  import flash.events.Event;
  import flash.events.EventDispatcher;
  import flash.events.IOErrorEvent;
  import flash.events.OutputProgressEvent;
  import flash.events.ProgressEvent;
  import flash.events.SecurityErrorEvent;
  import flash.net.Socket;
  import flash.system.Security;
  import flash.utils.ByteArray;
  import flash.utils.Dictionary;
  import flash.utils.clearTimeout;
  import flash.utils.setTimeout;
  import pomelo.interfaces.IMessage;
  import pomelo.interfaces.IPackage;

  [Event(name="handshake", type="pomelo.PomeloEvent")]
  [Event(name="kicked", type = "pomelo.PomeloEvent")]
  [Event(name="close", type = "flash.events.Event")]
  [Event(name="ioError", type="flash.events.IOErrorEvent")]
  [Event(name="securityError", type="flash.events.SecurityErrorEvent")]

  public class Pomelo extends EventDispatcher {

    public static const info:Object = {
      sys: {
        version: "1.0.0",
        type: "pomelo-flash-tcp",
        pomelo_version:"1.0.x"
      }
    };
    public var requests:Dictionary = new Dictionary(true);
    public var heartbeat:int;

    private var _handshake:Function;
    private var _socket:Socket;
    private var _hb:uint;

    private var _package:IPackage;
    private var _message:IMessage;

    private var _pkg:Object;

    private var _routesAndCallbacks:Array = new Array();

    public function Pomelo():void {
      _package = new Package();
      _message = new Message(requests);
    }

    public function init(host:String,
        port:int,
        user:Object = null,
        callback:Function = null,
        timeout:int = 8000,
        cross:int = 3843):void {
      info.user = user;
      _handshake = callback;

      Security.loadPolicyFile("xmlsocket://" + host + ":" + cross);

      _socket = new Socket();
      _socket.timeout = timeout;
      _socket.addEventListener(Event.CONNECT, onConnect, false);
      _socket.addEventListener(Event.CLOSE, onClose, false, 0);
      _socket.addEventListener(OutputProgressEvent.OUTPUT_PROGRESS, onOutputProgress, false);
      _socket.addEventListener(ProgressEvent.SOCKET_DATA, onData, false);
      _socket.addEventListener(IOErrorEvent.IO_ERROR, onIOError, false);
      _socket.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onSecurityError, false);

      _socket.connect(host, port);
    }

    public function disconnect():void {
      if (_socket && _socket.connected){
        _socket.close();
      }
      if (_hb) clearTimeout(_hb);
    }

    public function request(route:String, msg:Object, callback:Function = null):void {
      if (!route || !route.length) return;

      if (callback == null) {
        this.notify(route, msg);
        return;
      }

      var req:Request = new Request(route, callback);
      requests[req.id] = req;

      send(req.id, req.route, msg || {});
    }

    public function notify(route:String, msg:Object):void {
      send(0, route, msg || {});
    }

    public function on(route:String, callback:Function):void {
      this.addEventListener(route, callback, false);
      _routesAndCallbacks.push([route, callback]);
    }

    public function beat():void {
      clearTimeout(_hb);
      _hb = 0;

      if (_socket && _socket.connected) {
        _socket.writeBytes(_package.encode(Package.TYPE_HEARTBEAT));
        _socket.flush();
      }
    }

    private function send(reqId:int, route:String, msg:Object):void {
      var byte:ByteArray;

      byte = _message.encode(reqId, route, msg);
      byte = _package.encode(Package.TYPE_DATA, byte);

      if (_socket && _socket.connected) {
        _socket.writeBytes(byte);
        _socket.flush();
      }
    }

    private function onConnect(e:Event):void {
      _socket.writeBytes(_package.encode(Package.TYPE_HANDSHAKE, Protocol.strencode(JSON.stringify(info))));
      _socket.flush();
    }

    private function onOutputProgress(e:OutputProgressEvent):void {
    }

    private function onClose(e:Event):void {
      this.dispatchEvent(e);
    }

    private function onIOError(e:IOErrorEvent):void {
      this.dispatchEvent(e);
    }

    private function onSecurityError(e:SecurityErrorEvent):void {
      this.dispatchEvent(e);
    }

    private function onData(e:ProgressEvent):void {
      while (_socket && _socket.connected && _socket.bytesAvailable) {
        if (_pkg) {
          if (_socket.bytesAvailable >= _pkg.length) {
            _pkg.body = new ByteArray();
            if (_pkg.length) _socket.readBytes(_pkg.body, 0, _pkg.length);
          }
          else {
            break;
          }
        }
        else if (_socket.bytesAvailable >= 4) {
          _pkg = _package.decode(_socket);
        }

        if (_pkg && _pkg.body) {
          switch(_pkg.type) {
            case Package.TYPE_HANDSHAKE:
              var message:String = _pkg.body.readUTFBytes(_pkg.body.length);
              _pkg.body.clear();
              delete _pkg.body;
              delete _pkg.type;
              _pkg = null;

              var response:Object = JSON.parse(message);

              if (response.code == 200) {
                if (response.sys) {
                  Routedic.init(response.sys.dict);
                  Protobuf.init(response.sys.protos);

                  this.heartbeat = response.sys.heartbeat;
                }

                _socket.writeBytes(_package.encode(Package.TYPE_HANDSHAKE_ACK));
                _socket.flush();

                this.dispatchEvent(new PomeloEvent(PomeloEvent.HANDSHAKE));
              }

              if (_handshake != null) _handshake.call(this, response);

              break;

            case Package.TYPE_HANDSHAKE_ACK:
              _pkg.body.clear();
              delete _pkg.body;
              delete _pkg.type;
              _pkg = null;

              break;

            case Package.TYPE_HEARTBEAT:
              _pkg.body.clear();
              delete _pkg.body;
              delete _pkg.type;
              _pkg = null;

              if (this.heartbeat) {
                _hb = setTimeout(beat, this.heartbeat * 1000);
              }

              break;

            case Package.TYPE_DATA:
              var msg:Object = _message.decode(_pkg.body);

              _pkg.body.clear();
              delete _pkg.body;
              delete _pkg.type;
              _pkg = null;

              if (!msg.id) {
                this.dispatchEvent(new PomeloEvent(msg.route, msg.body));
              }
              else if (requests[msg.id]) {
                requests[msg.id].callback.call(this, msg.body);
                requests[msg.id] = null;
              }

              break;

            case Package.TYPE_KICK:
              _pkg.body.clear();
              delete _pkg.body;
              delete _pkg.type;
              _pkg = null;

              this.dispatchEvent(new PomeloEvent(PomeloEvent.KICKED));

              break;
          }
        }
      }
    }

    public function get message():IMessage {
      return _message;
    }

    public function set message(value:IMessage):void {
      _message = value;
    }

    public function destroy():void {
      for (var r:int = _routesAndCallbacks.length - 1; r >= 0; r--) {
        this.removeEventListener(_routesAndCallbacks[r][0], _routesAndCallbacks[r][1]);
      }

      _socket.removeEventListener(Event.CONNECT, onConnect);
      _socket.removeEventListener(Event.CLOSE, onClose);
      _socket.removeEventListener(OutputProgressEvent.OUTPUT_PROGRESS, onOutputProgress);
      _socket.removeEventListener(ProgressEvent.SOCKET_DATA, onData);
      _socket.removeEventListener(IOErrorEvent.IO_ERROR, onIOError);
      _socket.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, onSecurityError);

      try {
        _socket.flush();
      }
      catch (e:Error) {
        ;
      }
      _socket = null;
    }

  }

}

