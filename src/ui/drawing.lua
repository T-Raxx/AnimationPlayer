return function(A)
    A.UI = { _stub = true }
    A.notify = function(msg) print("[AnimPlayer] notify:", msg) end
end
