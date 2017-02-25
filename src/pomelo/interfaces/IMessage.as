package pomelo.interfaces {

  import flash.utils.ByteArray;

  public interface IMessage {

    function encode(id:uint, route:String, msg:Object):ByteArray;

    function decode(buffer:ByteArray):Object;

  }

}

