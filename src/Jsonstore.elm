module Jsonstore exposing
    ( Json, decode, encode, encodeList, decodeList, map
    , bool, int, float, string, dict
    , object, toJson, with, withList, withMaybe
    , update, get, insert, delete
    )

{-|


## Decoding and Encoding

@docs Json, decode, encode, encodeList, decodeList, map


## Basics

@docs bool, int, float, string, dict


## Dealing with Objects

@docs object, toJson, with, withList, withMaybe


## Http Requests

@docs update, get, insert, delete

-}

import Dict exposing (Dict)
import Http exposing (Error, Resolver)
import Json.Decode as D exposing (Decoder)
import Json.Encode as E exposing (Value)
import Task exposing (Task)


{-| The Json type combines both the Json Decoder and Encoder.
-}
type Json a
    = Json ( D.Decoder a, a -> Value )


{-| -}
map : (a -> b) -> (b -> a) -> Json a -> Json b
map dFun eFun (Json ( d, e )) =
    Json ( D.map dFun d, eFun >> e )


{-|

    import Json.Decode as D

    "1" |> (int |> decode |> D.decodeString) --> Ok 1

-}
int : Json Int
int =
    Json ( D.int, E.int )


{-|

    import Json.Decode as D

    "3.14" |> (float |> decode |> D.decodeString) --> Ok 3.14

-}
float : Json Float
float =
    Json ( D.float, E.float )


{-|

    import Json.Decode as D

    "\"Hello World\""
    |> (string |> decode |> D.decodeString)
    --> Ok "Hello World"

-}
string : Json String
string =
    Json ( D.string, E.string )


{-|

    import Json.Decode as D

    "true"
    |> (bool |> decode |> D.decodeString)
    --> Ok True

-}
bool : Json Bool
bool =
    Json ( D.bool, E.bool )


{-|

    import Json.Decode as D
    import Dict exposing (Dict)

    "{\"value\":42}"
    |> (int |> dict |> decode |> D.decodeString)
    --> Ok (Dict.singleton "value" 42)

-}
dict : Json a -> Json (Dict String a)
dict (Json ( d, e )) =
    Json ( d |> D.dict, E.dict identity e )


type JsonObject obj a
    = JsonObject ( Decoder obj, List ( String, a -> Value ) )


{-| -}
with : String -> Json a -> (obj -> a) -> JsonObject (a -> fun) obj -> JsonObject fun obj
with name (Json json) value (JsonObject ( d, e )) =
    JsonObject
        ( d
            |> D.map2 (\f fun -> fun f)
                (D.field name (json |> Tuple.first))
        , e |> (::) ( name, \o -> (json |> Tuple.second) (o |> value) )
        )


{-| -}
withList : String -> Json a -> (obj -> List a) -> JsonObject (List a -> fun) obj -> JsonObject fun obj
withList name (Json json) value (JsonObject ( d, e )) =
    JsonObject
        ( d
            |> D.map2 (\f fun -> fun f)
                ((D.map (Maybe.withDefault []) << D.maybe << D.field name) (json |> Tuple.first |> D.list))
        , e |> (::) ( name, \o -> E.list (json |> Tuple.second) (o |> value) )
        )


{-| -}
withMaybe : String -> Json a -> (obj -> Maybe a) -> JsonObject (Maybe a -> fun) obj -> JsonObject fun obj
withMaybe name (Json json) value (JsonObject ( d, e )) =
    JsonObject
        ( d
            |> D.map2 (\f fun -> fun f)
                (D.maybe <| D.field name (json |> Tuple.first))
        , e
            |> (::)
                ( name
                , \o ->
                    (Maybe.map (json |> Tuple.second)
                        >> Maybe.withDefault E.null
                    )
                        (o |> value)
                )
        )


{-|

    import Json.Decode as D

    type alias Obj =
        { value : Int
        , name : String
        }

    "{\"value\":42,\"name\":\"Elm\"}"
    |> ( object Obj
        |> with "value" int .value
        |> with "name" string .name
        |> toJson
        |> decode
        |> D.decodeString
        )
    --> Ok {value=42,name="Elm"}

-}
object : obj -> JsonObject obj a
object fun =
    JsonObject ( D.succeed fun, [] )


{-| -}
toJson : JsonObject obj obj -> Json obj
toJson =
    \(JsonObject ( d, e )) ->
        Json
            ( d
            , e
                |> (\l ->
                        \obj ->
                            l
                                |> List.map (\( name, fun ) -> ( name, fun obj ))
                                |> List.reverse
                                |> E.object
                   )
            )


{-| Returns the encoder for a List of a Json type
-}
encodeList : Json a -> List a -> Value
encodeList (Json ( _, fun )) =
    E.list fun


{-| Returns the decoder for a List of a Json type
-}
decodeList : Json a -> D.Decoder (List a)
decodeList (Json ( fun, _ )) =
    D.list fun


{-| Returns the decoder of a Json type
-}
decode : Json a -> D.Decoder a
decode (Json ( fun, _ )) =
    fun


{-| Returns the encoder of a Json type
-}
encode : Json a -> a -> Value
encode (Json ( _, fun )) =
    fun



-------------------------------------
-- HTTP
-------------------------------------


resolve : D.Decoder a -> Resolver Error a
resolve decoder =
    Http.stringResolver <|
        \response ->
            case response of
                Http.BadUrl_ url ->
                    Err (Http.BadUrl url)

                Http.Timeout_ ->
                    Err Http.Timeout

                Http.NetworkError_ ->
                    Err Http.NetworkError

                Http.BadStatus_ metadata _ ->
                    Err (Http.BadStatus metadata.statusCode)

                Http.GoodStatus_ _ body ->
                    case D.decodeString decoder body of
                        Ok value ->
                            Ok value

                        Err err ->
                            Err (Http.BadBody <| D.errorToString <| err)


resolveWhatever : Resolver Error ()
resolveWhatever =
    Http.stringResolver <|
        \response ->
            case response of
                Http.BadUrl_ url ->
                    Err (Http.BadUrl url)

                Http.Timeout_ ->
                    Err Http.Timeout

                Http.NetworkError_ ->
                    Err Http.NetworkError

                Http.BadStatus_ metadata _ ->
                    Err (Http.BadStatus metadata.statusCode)

                Http.GoodStatus_ _ _ ->
                    Ok ()


{-| Inserts a new Element.

Do not use this function to update fields, use update instead.

There is a max limit of 100kb that can be inserted at once.
Therefore never try to update a full list of object,
rather send an seperate update/delete file for every entry of the list.

-}
insert : String -> Value -> Task Error ()
insert url value =
    Http.task
        { method = "POST"
        , headers = []
        , url = url
        , body = Http.jsonBody value
        , resolver = resolveWhatever
        , timeout = Nothing
        }


{-| Deletes an Element.

Will be successfull even if the content is empty.

-}
delete : String -> Task Error ()
delete url =
    Http.task
        { method = "DELETE"
        , headers = []
        , url = url
        , body = Http.emptyBody
        , resolver = resolveWhatever
        , timeout = Nothing
        }


{-| Gets an Element

Returns `Nothing` if the element does not exist.

-}
get : String -> Decoder a -> Task Error (Maybe a)
get url decoder =
    Http.task
        { method = "GET"
        , headers = []
        , url = url
        , body = Http.emptyBody
        , resolver = resolve <| D.field "result" <| D.nullable <| decoder
        , timeout = Nothing
        }


{-| First gets the value, then either inserts a new value or does nothing

Use delete if you want to delete an element.

There is a max limit of 100kb that can be inserted at once.
Therefore never try to update a full list of object,
rather send an seperate update/delete file for every entry of the list.

-}
update : String -> Json a -> (a -> a) -> Task Error ()
update url json fun =
    get url (json |> decode)
        |> Task.andThen
            (Maybe.map (fun >> encode json >> insert url)
                >> Maybe.withDefault (Task.succeed ())
            )
