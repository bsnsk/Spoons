--- === Leanpub ===
---
--- Spoon to track and notify about Leanpub builds.
---
--- Download:
--- https://github.com/Hammerspoon/Spoons/raw/master/Spoons/Leanpub.spoon.zip

local obj={}
obj.__index = obj

-- Metadata
obj.name     = "Leanpub"
obj.version  = "0.2"
obj.author   = "Diego Zamboni <diego@zzamboni.org>"
obj.homepage = "https://github.com/Hammerspoon/Spoons"
obj.license  = "MIT - https://opensource.org/licenses/MIT"

--- Leanpub.logger
--- Variable
--- Logger object used within the Spoon. Can be accessed to set the
--- default log level for the messages coming from the Spoon.
obj.logger = hs.logger.new('Leanpub')

--- Leanpub.watch_books
--- Variable
--- List of books to watch (by default an empty list). Each element of
--- the list must be a table containing the following keys:
---  * slug - the web page "slug" of the book to watch. The slug of a
---    book can be set under the "Book Web Page / Web Page URL" menu
---    section in Leanpub.
---  * icon - optional icon to show in the notifications for the book,
---    as an hs.image object. If not specified, and if
---    `fetch_leanpub_covers` is `true`, then the icon is generated
---    automatically from the book cover.
obj.watch_books = {}

--- Leanpub.api_key
--- Variable
--- String containing the key to use for Leanpub API requests. Get it
--- from your Leanpub account under the "Author / Your API Key" menu
--- section. No default.
obj.api_key = ""

--- Leanpub.check_interval
--- Variable
--- Integer containing the interval (in seconds) at which the book
--- status is checked. Default 5.
obj.check_interval = 5

--- Leanpub.fetch_leanpub_covers
--- Variable
--- Boolean indicating whether we should try to fetch book covers from
--- Leanpub (default true)
obj.fetch_leanpub_covers = true

--- Leanpub.persistent_notification
--- Variable
--- Table specifying the Leanpub status for which notifications should
--- not disappear automatically. The indices correspond to the values
--- of the `status` field returned by the Leanpub API. Possible values
--- are `working` and `complete`. Default `{ complete = true }` to
--- keep the "Book generation complete" messages.
obj.persistent_notification = { complete = true }

--- Leanpub:getBookStatus(slug, callback)
--- Method
--- Asynchronously get the status of a book given its slug.
---
--- Parameters:
---  * slug - URL "slug" of the book to check. The slug of a book is
---    the part of the URL for your book after https://leanpub.com/.
---  * callback - function to which the book status will be passed
---    when the data is received. This function will be passed a
---    single argument, a table containing the fields returned by the
---    Leanpub API. If the book is not being built at the moment, an
---    empty table is passed. If an error occurs, the value passed
---    will be `nil`. Samples of the return values can be found at
---    https://leanpub.com/help/api#getting-the-job-status
---
--- Returns:
---  * No return value
function obj:getBookStatus(slug, callback)
  local url = string.format("https://leanpub.com/%s/job_status?api_key=%s",
                            slug, self.api_key)
  self.logger.df("Fetching status for book '%s'", slug)
  hs.http.asyncGet(url, {},
                   function(s, b, h)
                     self:_getBookStatusCallback(slug,s,b,h,callback)
                   end)
end

function obj:_getBookStatusCallback(slug,status,body,headers,callback)
  if status == 200 then
    self.logger.df("  Status of book '%s': %s", slug, body)
    callback(hs.json.decode(body))
  else
    -- status==0 means no network (which might be common if you use a
    -- laptop), so we don't produce an error in that case. Otherwise
    -- we print an error and call the callback with nil
    if status ~= 0 then
      self.logger.ef("  Error: %s %s %s", status, body, hs.inspect(headers))
      callback(nil)
    end
  end
end

obj.last_status = {}

--- Leanpub:displayBookStatus(book)
--- Method
--- Display a notification with the current build status of a book.
--- Only produce a notification if the current status is different
--- than the last known one (from the last time `displayBookStatus`
--- was run for the same book).
---
--- Parameters:
---  * book - table containing the information of the book to
---    check. The table must contain the following fields:
---    * slug - URL "slug" of the book to check. The slug is the part
---      of the book URL after https://leanpub.com/.
---    * icon - optional icon to show in the notifications for the
---      book, as an `hs.image` object. If this field is not specified
---      but `fetch_leanpub_covers` is true (the default value), this
---      method attempts to fetch the book cover from Leanpub. If the
---      cover can be retrieved, it gets stored in the icon field so
---      it doesn't get fetched every time. You can disable cover
---      fetching for individual books by setting this field
---      explicitly to `false`
---
--- Returns:
---  * A Lua table containing the status (may be empty), nil if an
---    error occurred

function obj:displayBookStatus(book)
  -- Fetches and stores the cover if needed
  self:fetchBookCover(book)
  -- Gets and displays the book status if needed
  self:getBookStatus(book.slug,
                     function(status)
                       self:_displayBookStatusCallback(book, status)
                     end)
end

function obj:_displayBookStatusCallback(book, status)
  if status then
    local step = status.message
    if step and step ~= self.last_status[book.slug] then
      -- Create base notification, with just the text
      local n = hs.notify.new({
          title = status.name,
          subTitle = string.format("Step %d of %d",status.num,status.total),
          informativeText = step
      })
      -- If we have an icon, put it in the notification
      if book.icon then
        n:setIdImage(book.icon)
      end
      -- If message should be persistent, set timeout to 0
      if self.persistent_notification[status.status] then
        n:withdrawAfter(0)
      end
      -- Finally! Generate the notification.
      n:send()
    end
    self.last_status[book.slug] = step
  end
end

--- Leanpub:fetchBookCover(book)
--- Method
--- Fetch the cover of a book.
---
--- Parameters:
---  * book - table containing the book information. The icon gets
---    stored in its `icon` field when it can be fetched.
---
--- Returns:
---  * No return value
---
--- Side effects:
---  * Stores the icon in the book data structure
function obj:fetchBookCover(book)
  -- If no icon is given, fetch it from Leanpub. Explicitly check
  -- against nil to allow disabling the icon by specifying its
  -- value as `false`
  if book.icon == nil and self.fetch_leanpub_covers then
    local url = string.format("https://leanpub.com/%s.json?api_key=%s",
                              book.slug, self.api_key)
    self.logger.df("Fetching info for book '%s'", book.slug)
    hs.http.asyncGet(url, {},
                     function(s,b,h)
                       self:_fetchBookCoverCallback(book,s,b,h)
                     end)
  end
end

function obj:_fetchBookCoverCallback(book, status, body, headers)
  if status == 200 then
    local info = hs.json.decode(body)
    book.icon = hs.image.imageFromURL(info.title_page_url or "")
    if book.icon == nil then
      self.logger.df("No cover available from Leanpub for book '%s'", book.slug)
      book.icon = false
    else
      self.logger.df("Storing cover for book '%s'", book.slug)
    end
  end
end

--- Leanpub:displayAllBookStatus()
--- Method
--- Check and display (if needed) the status of all the books in `watch_books`
function obj:displayAllBookStatus()
  for i,book in ipairs(self.watch_books) do
    self:displayBookStatus(book)
  end
end

obj.timer = nil

--- Leanpub:start()
--- Method
--- Start periodic check for book status, checking every
--- check_interval seconds.
function obj:start()
  self.timer = hs.timer.new(self.check_interval,
                            function()
                              self:displayAllBookStatus()
                            end):start()
end

--- Leanpub:stop()
--- Method
--- Stops periodic check for book status, if enabled.
--- check_interval seconds.
function obj:stop()
  if self.timer ~= nil then
    self.timer:stop()
    self.timer = nil
  end
end

return obj
