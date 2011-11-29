
var WS;
var REFS;
var SERVER;
var CALLBACKS;
var handshaked;
var isWebsocket;
var TASKS;

// WebSocket Implementation
function djs_start_websocket(server) {
    WS = new WebSocket(server);
    WS.onopen = on_open;
    WS.onclose = on_close;
    WS.onmessage = on_message;
    WS.onerror = on_error;
    handshaked = false;
    REFS = new Array();
    TASKS = new Array();
    CALLBACKS = new Array();
    isWebsocket = true;
}

function websocket_handshake() {
    WS.send("0\x000\x00");
}

function on_open() {
    websocket_handshake();
    console.log("opened");
}

function on_close() {
    console.log("closed");
}

function on_message(event) {
    if (!handshaked) {
        handshaked = true;
        DJS_ID = event.data;
        WS.send("1\x00" + DJS_ID + "\x00");
    } else {
        if (event.data == "\x00") {
            return;
        }
        var rsp = djs_eval(event.data);
        WS.send("2\x00" + DJS_ID + "\x00" + rsp);
    }
}

function on_error(error) {
    console.log("error");
}

function oncallback(cid, method, event) {
    WS.send("5\x00" + cid + "\x00" + method);
}

// AJAX Implementation
function djs_start_ajax(server) {
    SERVER = server;
    REFS = new Array();
    TASKS = new Array();
    CALLBACKS = new Array();
    isWebsocket = false;

    handshake();
}

function djs_send(msg, callback) {
    message(msg, callback);
}

function getXmlHttpRequestObject() {
    var xhr;
    if (XMLHttpRequest) {
        xhr = new XMLHttpRequest();
    } else {
        try {
            xhr = new ActiveXObject('MSXML2.XMLHTTP.6.0');
        } catch (e) {
            try {
                xhr = new ActiveXObject('MSXML2.XMLHTTP.3.0');
            } catch (e) {
                try {
                    xhr = new ActiveXObject('MSXML2.XMLHTTP');
                } catch (e) {
                    xhr = null;
                    alert("This browser does not support XMLHttpRequest.");
                }
            }
        }
    }

    return xhr;
}

function handshake() {
    var xhr = getXmlHttpRequestObject();
    xhr.open("POST", SERVER);
    xhr.setRequestHeader("Content-Type", "text/plain");
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4 && xhr.status === 200) {
            if (xhr.responseText == "\x00") {
                return;
            }
            var id = xhr.responseText;
            connect(id);
        }
    };
    xhr.send("0\x000\x00");
}

function connect(id) {
    var xhr = getXmlHttpRequestObject();
    xhr.open("POST", SERVER);
    xhr.setRequestHeader("Content-Type", "text/plain");
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4 && xhr.status === 200) {
            var rsp = xhr.responseText;
            if (rsp == "\x00") {
                return;
            }
            if (rsp == "") {
                reconnect(id);
                return;
            }
            var req = djs_eval(rsp);
            response(id, req);
        }
    };
    xhr.send("1\x00" + id + "\x00");
}

function reconnect(id) {
    var xhr = getXmlHttpRequestObject();
    xhr.open("POST", SERVER);
    xhr.setRequestHeader("Content-Type", "text/plain");
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4 && xhr.status === 200) {
            var rsp = xhr.responseText;
            if (rsp == "\x00") {
                return;
            }
            if (rsp == "") {
                reconnect(id);
                return;
            }
            var req = djs_eval(rsp);
            response(id, req);
        }
    };
    xhr.send("6\x00" + id + "\x00");
}

function response(id, rsp) {
    var xhr = getXmlHttpRequestObject();
    xhr.open("POST", SERVER);
    xhr.setRequestHeader("Content-Type", "text/plain");
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4 && xhr.status === 200) {
            var rsp = xhr.responseText;
            if (rsp == "\x00") {
                return;
            }
            if (rsp == "") {
                reconnect(id);
                return;
            }
            var req = djs_eval(rsp);
            response(id, req);
        }
    };
    xhr.send("2\x00" + id + "\x00" + rsp);
}

function callback(cid, method, event) {
    var xhr = getXmlHttpRequestObject();
    xhr.open("POST", SERVER);
    xhr.setRequestHeader("Content-Type", "text/plain");
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4 && xhr.status === 200) {
            var rsp = xhr.responseText;
            var id = rsp.substring(0, rsp.indexOf("\x00"));
            if (rsp == "\x00") {
                return;
            }
            var req = djs_eval(rsp.substring(rsp.indexOf("\x00") + 1));
            response(id, req);
        }
    }
    xhr.send("5\x00" + cid + "\x00" + method);
}

function rpc(id) {
    var xhr = getXmlHttpRequestObject();
    xhr.open("POST", SERVER);
    xhr.setRequestHeader("Content-Type", "text/plain");
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4 && xhr.status === 200) {
            var rsp = xhr.responseText;
            if (rsp == "\x00") {
                return;
            }
            var req = djs_eval(rsp);
            response(id, req);
        }
    }
    xhr.send("7\x00" + id + "\x00");
}

function djs_eval(json) {
    var reqs = json.split("\x00");
    var info;
    var id;
    var cid;
    var obj;
    var content;
    var args;
    var result;
    var i;
    if (reqs[0] == "1") {
        for (i = 1; i < reqs.length; i++) {
            info = eval("(" + reqs[i] + ")");
            REFS[info.id].origin = info.origin;
        }
    } else {
        for (i = 1; i < reqs.length; i++) {
            TASKS.push(reqs[i]);
        }
    }

    var req;
    var rsp = "{";
    while (TASKS.length > 0) {
        req = TASKS.shift();
        info = eval("(" + req + ")");
        id = info.id;
        cid = info.cid;
        obj = info.type;
        content = info.content;
        args = info.args;

        if (obj == "rpc") {
            rpc(content);
            // TODO
            continue;
        }

        if (info.content.indexOf("{}") == 0) {
            obj[info.content.substring(2)] = createCallback(cid, info.args[0]);
            result = null;
        } else {
            // TODO obj[content]
            if (isPrimitive(obj) && !obj[content]) {
                to_ruby_object(info.id, null);
                info.type = obj;
                return toRubyHash(info);
            }

            if (args && args.length > 0) {
                if (content.match(/^.+=$/)) {
                    obj[content.substring(0, content.length - 1)] = args[0];
                    result = null;
                } else {
                    // TODO
                    if (args.length > 1) {
                        result = obj[content].apply(obj, args);
                    } else {
                        result = obj[content](args[0]);
                    }
                }
            } else {
                if (typeof obj[content] == "function") {
                    result = obj[content]();
                } else {
                    result = obj[content];
                }
            }
        }

        obj = to_ruby_object(id, result);
        if (obj) {
            rsp += id + "=>" + obj + ",";
        }
    }

    if (rsp.length > 1) {
        rsp = rsp.substring(0, rsp.length - 1) + "}";
    } else {
        rsp += "}";
    }
    return rsp;
}

function createRefObj(id, obj) {
    var refObj = new RefObj(id, obj);
    REFS[id] = refObj;
    return refObj;
}

function createCallback(cid, method) {
    return function(cid, method) {
        return function(e) {
            if (isWebsocket) {
                oncallback(cid, method, e);
            } else {
                callback(cid, method, e);
            }
        }
    }(cid, method);
}

function RefObj(id, obj) {
    this.id = id;
    this.origin = obj;
}

function to_ruby_object(id, obj) {
    if (obj == undefined || obj == null) {
        return null;
    }

    // TODO all type?
    var type = typeof obj;
    if (type == "string") {
        return "'" + obj.replace(/'/g, "\\'") + "'";
    } else if (type == "number" || type == "boolean") {
        return obj;
    } else {
        createRefObj(id, obj);
        return null;
    }
}

function isPrimitive(obj) {
    var type = typeof obj;
    return type == "string" || type == "number" || type == "boolean";
}

function toRubyHash(hash) {
    var ret = '{';
    for (key in hash) {
        ret += '"' + key + '"=>';
        if (typeof hash[key] == "string") {
            ret += '"' + hash[key] + '",';
        } else {
            // TODO
            if (hash[key] instanceof Array && hash[key].length == 0) {
                ret += '[],';
            } else {
                ret += hash[key] + ',';
            }
        }
    }
    if (ret.length > 1) {
        ret = ret.substring(0, ret.length - 1);
    }
    ret += '}';
    return ret;
}
