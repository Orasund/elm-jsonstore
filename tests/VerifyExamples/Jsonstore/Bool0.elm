module VerifyExamples.Jsonstore.Bool0 exposing (..)

-- This file got generated by [elm-verify-examples](https://github.com/stoeffel/elm-verify-examples).
-- Please don't modify this file by hand!

import Test
import Expect

import Jsonstore exposing (..)
import Json.Decode as D







spec0 : Test.Test
spec0 =
    Test.test "#bool: \n\n    \"true\" |> (bool |> decode |> D.decodeString)\n    --> Ok True" <|
        \() ->
            Expect.equal
                (
                "true" |> (bool |> decode |> D.decodeString)
                )
                (
                Ok True
                )