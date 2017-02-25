package pomelo {

  public class Request {

    private static var reqId:int = 0;

    public var id:int;
    public var route:String;
    public var callback:Function;

    public function Request(route:String, callback:Function = null):void {
      this.id = ++reqId;
      this.route = route;
      this.callback = callback;
    }

  }

}

