xquery version "1.0-ml";

(: Copyright 2011-2019 MarkLogic Corporation.  All Rights Reserved. :)

import module namespace rsrcmodcom = "http://marklogic.com/rest-api/models/resource-model-common"
    at "../models/resource-model-common.xqy";

import module namespace rsrcmodqry = "http://marklogic.com/rest-api/models/resource-model-query"
    at "../models/resource-model-query.xqy";

import module namespace parameters = "http://marklogic.com/rest-api/endpoints/parameters"
    at "../endpoints/parameters.xqy";

import module namespace eput = "http://marklogic.com/rest-api/lib/endpoint-util"
    at "../lib/endpoint-util.xqy";

import module namespace lid = "http://marklogic.com/util/log-id"
    at "/MarkLogic/appservices/utils/log-id.xqy";

declare default function namespace "http://www.w3.org/2005/xpath-functions";
declare option xdmp:mapping "false";

declare option xdmp:transaction-mode "auto";

declare private function local:rsrcmod-callback(
    $request-result   as xs:string,
    $plugin-name      as xs:string,
    $has-content      as xs:boolean,
    $response-type    as xs:string?,
    $response-status  as xs:anyAtomicType*,
    $response-headers as item()*
) as empty-sequence()
{
    if ($request-result = ($rsrcmodqry:RESOURCE_APPLIED, $rsrcmodqry:RESOURCE_READ))
    then ()
    else error((),"RESTAPI-INTERNALERROR",
        concat("unknown result ",$request-result," for ",$plugin-name)),

    rsrcmodcom:environment(
        $plugin-name,$has-content,$response-type,$response-status,$response-headers
    )
};

let $headers     := eput:get-request-headers()
let $method      := xdmp:get-request-method()
let $body        :=
    if (not($method = ("POST")) or starts-with(
        head(map:get($headers,"content-type")), "application/x-www-form-urlencoded"
        )) then ()
    else xdmp:get-request-body()
let $params      := map:new()
    =>parameters:query-parameter("name",true(),false())
    =>parameters:query-parameter("txid",false(),false())
    =>parameters:query-parameter("database",false(),false())
    =>parameters:query-parameter("trace",false(),true(),(),"http://marklogic.com/xdmp/privileges/rest-tracer")
    =>parameters:query-parameters-passthrough("^rs:")
let $extra-names := parameters:validate-parameter-names($params,())
return (
    if (empty($extra-names)) then ()
    else error((),"REST-UNSUPPORTEDPARAM", concat(
        "invalid parameters: ",string-join($extra-names,", ")," for ",map:get($params,"name")
        )),

    lid:enable(map:get($params,"trace")),

    if (rsrcmodqry:check-untraced()) then ()
    else lid:log($rsrcmodqry:trace-id,"service-query-endpoint",
        map:entry("method",$method)=>map:with("headers",$headers)=>map:with("parameters",$params)
        ),

    switch ($method)
    case "GET" return (
        xdmp:security-assert("http://marklogic.com/xdmp/privileges/rest-reader", "execute"),
        rsrcmodqry:exec-get($headers,$params,local:rsrcmod-callback#6)
        )
    case "POST" return (
        xdmp:security-assert("http://marklogic.com/xdmp/privileges/rest-reader", "execute"),
        rsrcmodqry:exec-post($headers,$params,$body,local:rsrcmod-callback#6)
            [not(xdmp:get-response-code()[1] eq 204)]
        )
    default return error((),"RESTAPI-INVALIDREQ",
        concat("unsupported method ",$method," for ",map:get($params,"name"))
        )
    )
