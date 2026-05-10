import Blob "mo:base/Blob";
import Text "mo:base/Text";
import Principal "mo:base/Principal";

persistent actor {
  // Variant types for testing
  type Color = { #Red; #Green; #Blue };
  type Result = { #success : Text; #error : Text };
  type Status = { #active : { id : Nat }; #inactive };
  public query func responseNull() : async Null {
    return null;
  };

  public query func responseEmpty() : async () {
    return ();
  };

  public query func boolFunc() : async Bool {
    return true;
  };

  public query func intFunc() : async Int {
    return 1;
  };

  public query func int8Func() : async Int8 {
    return 1;
  };

  public query func int16Func() : async Int16 {
    return 1;
  };

  public query func int32Func() : async Int32 {
    return 1;
  };

  public query func int64Func() : async Int64 {
    return 1;
  };

  public query func natFunc() : async Nat {
    return 1;
  };

  public query func nat8Func() : async Nat8 {
    return 1;
  };

  public query func nat16Func() : async Nat16 {
    return 1;
  };

  public query func nat32Func() : async Nat32 {
    return 1;
  };

  public query func nat64Func() : async Nat64 {
    return 1;
  };

  public query func floatFunc() : async Float {
    return 1.0;
  };

  public query func textFunc() : async Text {
    return "Hello, World!";
  };

  public query func blobFunc() : async Blob {
    return Text.encodeUtf8("Hello, World!");
  };

  public query func vecNatFunc() : async [Nat] {
    return [1, 2, 3, 4, 5];
  };

  public query func vecTextFunc() : async [Text] {
    return ["Hello", "World", "Candid", "Vector"];
  };

  public query func vecBoolFunc() : async [Bool] {
    return [true, false, true, false];
  };

  public query func vecIntFunc() : async [Int] {
    return [1, -2, 3, -4, 5];
  };

  public query func vecVecNatFunc() : async [[Nat]] {
    return [[1, 2], [3, 4, 5]];
  };

  public query func vecVecTextFunc() : async [[Text]] {
    return [["Hello", "World"], ["Candid", "Vector"]];
  };

  public query func vecVecBoolFunc() : async [[Bool]] {
    return [[true, false], [false, true]];
  };

  public query func vecVecIntFunc() : async [[Int]] {
    return [[1, -2], [3, -4, 5]];
  };
  public query func optTextSome() : async ?Text {
    return ?"Hello, Option!";
  };

  public query func optTextNone() : async ?Text {
    return null;
  };

  public query func optIntSome() : async ?Int {
    return ?1;
  };

  public query func optIntNone() : async ?Int {
    return null;
  };

  public query func optNatSome() : async ?Nat {
    return ?1;
  };

  public query func optNatNone() : async ?Nat {
    return null;
  };

  public query func optFloatSome() : async ?Float {
    return ?1.0;
  };

  public query func optFloatNone() : async ?Float {
    return null;
  };

  public query func optBoolSome() : async ?Bool {
    return ?true;
  };

  public query func optBoolNone() : async ?Bool {
    return null;
  };

  // record: 単純なレコードを返す
  public query func recordSimple() : async { name : Text; age : Int } {
    return { name = "Alice"; age = 30 };
  };

  // record: ネストしたレコードを返す
  public query func recordNested() : async { user : { id : Nat; active : Bool }; meta : { note : Text } } {
    return {
      user = { id = 1; active = true };
      meta = { note = "ok" }
    };
  };

  // variant: simple enum-like (no payload)
  public query func variantColorRed() : async Color { return #Red; };
  public query func variantColorGreen() : async Color { return #Green; };
  public query func variantColorBlue() : async Color { return #Blue; };

  // variant: with payload
  public query func variantResultOk() : async Result { return #success("ok"); };
  public query func variantResultErr() : async Result { return #error("ng"); };

  // variant: mixed null and record payload
  // public query func variantStatusActive() : async Status { return #active({ id = 1 }); };
  // public query func variantStatusInactive() : async Status { return #inactive; };

  // Principal type tests
  public query func principalFunc() : async Principal {
    return Principal.fromText("aaaaa-aa");
  };

  public query func principalAnonymous() : async Principal {
    return Principal.fromText("2vxsx-fae");
  };

  public query func principalCanister() : async Principal {
    return Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
  };
  
  // Function reference: returns a query function () -> (Text) on a fixed canister principal
  
  public query func greet(msg: Text): async Text {
    return "Hello, " # msg # "!";
  };
  
  public query func funcRefTextQuery() : async (shared query (Text) -> async Text) {
    return greet;
  };
};
