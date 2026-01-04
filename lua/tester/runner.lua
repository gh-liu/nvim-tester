local M = {}

function M.run(cmd, opts)
  opts = opts or {}

  if vim.fn.exists(':Dispatch') == 2 then
    local dispatch_cmd = cmd
    if opts.cwd then
      dispatch_cmd = "-dir=" .. opts.cwd .. " " .. cmd
    end
    vim.cmd("Dispatch " .. dispatch_cmd)
    return
  end

  vim.system(cmd, {
    text = true,
    cwd = opts.cwd,
  }, function(obj)
    if opts.on_complete then
      opts.on_complete(obj.stdout or "")
    end
  end)
end

return M
