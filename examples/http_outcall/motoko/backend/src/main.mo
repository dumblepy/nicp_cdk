import Blob "mo:base/Blob";
import Text "mo:base/Text";

//Actor
persistent actor {
  // 型定義をactor内で定義
  type HttpHeader = {
    name : Text;
    value : Text;
  };

  type HttpMethod = {
    #get; #post; #head;
  };

  type HttpResponsePayload = {
    status : Nat;
    headers : [HttpHeader];
    body : Blob;
  };

  type TransformArgs = {
    context : Blob;
    response : HttpResponsePayload;
  };

  type HttpRequestArgs = {
    url : Text;
    max_response_bytes : ?Nat;
    headers : [HttpHeader];
    body : ?Blob;
    method : HttpMethod;
    transform : ?{
      function : shared query (TransformArgs) -> async HttpResponsePayload;
      context : Blob;
    };
    is_replicated : ?Bool;
  };

  type IC = actor {
    http_request : HttpRequestArgs -> async HttpResponsePayload;
  };

  transient let ic : IC = actor("aaaaa-aa");

  //This method sends a GET request to a URL with a free API we can test.
  //This method returns Coinbase data on the exchange rate between USD and ICP
  //for a certain day.
  //The API response looks like this:
  //  [
  //     [
  //         1682978460, <-- start timestamp
  //         5.714, <-- lowest price during time range
  //         5.718, <-- highest price during range
  //         5.714, <-- price at open
  //         5.714, <-- price at close
  //         243.5678 <-- volume of ICP traded
  //     ],
  // ]

  //function to transform the response
  public query func transform(args : TransformArgs) : async HttpResponsePayload {
    {
      status = args.response.status;
      headers = []; // not interested in the headers
      body = args.response.body;
    };
  };

  func decodeBody(body : Blob) : Text {
    switch (Text.decodeUtf8(body)) {
      case (null) { "No value returned" };
      case (?y) { y };
    };
  };

  func toHttpRequestArgs(
    url : Text,
    method : HttpMethod,
    headers : [HttpHeader],
    body : ?Blob
  ) : HttpRequestArgs {
    let http_request : HttpRequestArgs = {
      url = url;
      max_response_bytes = null; // optional for request
      headers = headers;
      body = body;
      method = method;
      transform = ?{
        function = transform;
        context = Blob.fromArray([]);
      };
      // Toggle this flag to switch between replicated and non-replicated http outcalls.
      is_replicated = ?false;
    };
    return http_request;
  };

  func httpRequest(
    url : Text,
    method : HttpMethod,
    headers : [HttpHeader],
    body : ?Blob
  ) : async HttpResponsePayload {
    let http_request = toHttpRequestArgs(url, method, headers, body);
    await (with cycles = 230_949_972_000) ic.http_request(http_request);
  };

  public func httpbin_get() : async Text {
    let url = "https://httpbin.org/get";
    let headers = [{ name = "User-Agent"; value = "motoko-http-outcall" }];
    let http_response = await httpRequest(url, #get, headers, null);
    decodeBody(http_response.body);
  };

  public func httpbin_post() : async Text {
    let url = "https://httpbin.org/post";
    let headers = [
      { name = "User-Agent"; value = "motoko-http-outcall" },
      { name = "Content-Type"; value = "application/json" },
    ];
    let body = ?Text.encodeUtf8("{\"message\":\"hello from motoko\"}");
    let http_response = await httpRequest(url, #post, headers, body);
    decodeBody(http_response.body);
  };

  public query func post_args() : async HttpRequestArgs {
    let url = "https://httpbin.org/post";
    let headers = [
      { name = "User-Agent"; value = "motoko-http-outcall" },
      { name = "Content-Type"; value = "application/json" },
    ];
    let body = ?Text.encodeUtf8("{\"message\":\"hello from motoko\"}");
    return toHttpRequestArgs(url, #post, headers, body);
  };

  public func httpbin_head() : async Text {
    let url = "https://httpbin.org/get";
    let headers = [{ name = "User-Agent"; value = "motoko-http-outcall" }];
    let http_response = await httpRequest(url, #head, headers, null);
    decodeBody(http_response.body);
  };

  public query func transformFunc(): async (shared query (TransformArgs) -> async HttpResponsePayload) {
    return transform;
  };

  public query func transformBody(): async ?{
      function : shared query (TransformArgs) -> async HttpResponsePayload;
      context : Blob;
    } {
    return ?{
      function = transform;
      context = Blob.fromArray([]);
    };
  };

  public query func httpRequestArgs() : async HttpRequestArgs {
    let url = "https://httpbin.org/get";
    let headers = [{ name = "User-Agent"; value = "motoko-http-outcall" }];
    return toHttpRequestArgs(url, #get, headers, null);
  };
};
