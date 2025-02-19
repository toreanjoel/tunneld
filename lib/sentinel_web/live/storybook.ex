defmodule SentinelWeb.Live.Storybook do
  @moduledoc """
  The storybook liveview that will be used to render the components and testing UI
  """
  use SentinelWeb, :live_view

  @doc """
  Initialize the Story book
  """
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="bg-storybook-gradient">
      <div class="w-[960px] mx-auto p-4 text-white grid grid-cols-3 gap-4 items-center justify-items-center h-[100vh]">
        <!-- HEADERS -->
        <div class="text-center p-5 bg-primary rounded-md">
          <h1 class="font-main text-[2em]">Header 1</h1>
          <h2 class="font-main text-[1.5em]">Header 2</h2>
          <h3 class="font-main text-[1.17em]">Header 3</h3>
          <h4 class="font-main text-[1em]">Header 4</h4>
          <h5 class="font-main text-[0.83em]">Header 5</h5>
          <h6 class="font-main text-[0.67em]">Header 6</h6>
        </div>
        <!-- DEVICES -->
        <div class="grid grid-cols-2 gap-4">
          <div class="p-2 flex flex-col bg-primary rounded-lg w-[150px] h-[130px] hover:bg-secondary cursor-pointer">
            <div class="flex flex-row">
              <div class="grow">
                <.icon class="w-6 h-6 text-gray-1" name="hero-computer-desktop" />
              </div>
              <%!-- INPUT TOGGLE --%>
              <label class="relative inline-flex items-center cursor-pointer">
                <input type="checkbox" class="sr-only peer" />
                <div class="w-9 h-5 bg-light_purple
                  rounded-full
                  peer-checked:bg-purple
                  relative
                  after:content-[''] after:absolute after:top-[2px] after:left-[2px]
                  after:bg-white after:border-light_purple after:border after:rounded-full
                  after:h-4 after:w-4
                  after:transition-all peer-checked:after:translate-x-4">
                </div>
              </label>
            </div>
            <div class="grow" />
            <div class="font-main text-sm">_TrojanMorse</div>
            <div class="text-xs font-main">aa:bb:cc:dd:ee:ff</div>
          </div>
          <div class="p-2 flex flex-col bg-primary rounded-lg w-[150px] h-[130px] hover:bg-secondary cursor-pointer">
            <div class="flex flex-row">
              <div class="grow">
                <.icon class="w-6 h-6 text-gray-1" name="hero-tv" />
              </div>
              <%!-- INPUT TOGGLE --%>
              <label class="relative inline-flex items-center cursor-pointer">
                <input type="checkbox" checked class="sr-only peer" />
                <div class="w-9 h-5 bg-gray-2
                  rounded-full
                  peer-checked:bg-purple
                  relative
                  after:content-[''] after:absolute after:top-[2px] after:left-[2px]
                  after:bg-white after:border-gray-2 after:border after:rounded-full
                  after:h-4 after:w-4
                  after:transition-all peer-checked:after:translate-x-4">
                </div>
              </label>
            </div>
            <div class="grow" />
            <div class="font-main text-sm">LG TV</div>
            <div class="text-xs font-main">aa:bb:cc:dd:ee:ff</div>
          </div>
          <div class="p-2 flex flex-col bg-primary rounded-lg w-[150px] h-[130px] hover:bg-secondary cursor-pointer">
            <div class="flex flex-row">
              <div class="grow">
                <.icon class="w-6 h-6 text-gray-1" name="hero-device-phone-mobile" />
              </div>
              <%!-- INPUT TOGGLE --%>
              <label class="relative inline-flex items-center cursor-pointer">
                <input type="checkbox" checked class="sr-only peer" />
                <div class="w-9 h-5 bg-gray-2
                  rounded-full
                  peer-checked:bg-purple
                  relative
                  after:content-[''] after:absolute after:top-[2px] after:left-[2px]
                  after:bg-white after:border-gray-2 after:border after:rounded-full
                  after:h-4 after:w-4
                  after:transition-all peer-checked:after:translate-x-4">
                </div>
              </label>
            </div>
            <div class="grow" />
            <div class="font-main text-sm">Note 20</div>
            <div class="text-xs font-main">aa:bb:cc:dd:ee:ff</div>
          </div>
          <div class="p-2 flex flex-col bg-primary rounded-lg w-[150px] h-[130px] hover:bg-secondary cursor-pointer">
            <div class="flex flex-row">
              <div class="grow">
                <.icon class="w-6 h-6 text-gray-1" name="hero-computer-desktop" />
              </div>
              <%!-- INPUT TOGGLE --%>
              <label class="relative inline-flex items-center cursor-pointer">
                <input type="checkbox" class="sr-only peer" />
                <div class="w-9 h-5 bg-gray-2
                  rounded-full
                  peer-checked:bg-purple
                  relative
                  after:content-[''] after:absolute after:top-[2px] after:left-[2px]
                  after:bg-white after:border-gray-2 after:border after:rounded-full
                  after:h-4 after:w-4
                  after:transition-all peer-checked:after:translate-x-4">
                </div>
              </label>
            </div>
            <div class="grow" />
            <div class="font-main text-sm">Mac M1</div>
            <div class="text-xs font-main">aa:bb:cc:dd:ee:ff</div>
          </div>
        </div>
        <!-- PALLET -->
        <div class="grid grid-cols-4 gap-2">
          <div class="w-[50px] h-[50px] rounded bg-primary"></div>
          <div class="w-[50px] h-[50px] rounded bg-secondary"></div>
          <div class="w-[50px] h-[50px] rounded bg-yellow"></div>
          <div class="w-[50px] h-[50px] rounded bg-green"></div>
          <div class="w-[50px] h-[50px] rounded bg-red"></div>
          <div class="w-[50px] h-[50px] rounded bg-purple"></div>
          <div class="w-[50px] h-[50px] rounded bg-light_purple"></div>
          <div class="w-[50px] h-[50px] rounded bg-gray-1"></div>
          <div class="w-[50px] h-[50px] rounded bg-gray-2"></div>
          <div class="w-[50px] h-[50px] rounded bg-white"></div>
        </div>
        <!-- EDGE NODES -->
        <div class="grid grid-cols-4 gap-2">
          <div class="relative w-[50px] h-[50px] p-2 bg-primary flex items-center justify-center rounded-md hover:bg-secondary cursor-pointer">
            <.icon class="w-6 h-6" name="hero-cpu-chip" />
            <div class="absolute bottom-[5px] right-2 w-[5px] h-[5px] rounded-full bg-yellow"></div>
          </div>
          <div class="relative w-[50px] h-[50px] p-2 bg-primary flex items-center justify-center rounded-md hover:bg-secondary cursor-pointer">
            <.icon class="w-6 h-6" name="hero-circle-stack" />
            <div class="absolute bottom-[5px] right-2 w-[5px] h-[5px] rounded-full bg-green"></div>
          </div>
          <div class="relative w-[50px] h-[50px] p-2 bg-primary flex items-center justify-center rounded-md hover:bg-secondary cursor-pointer">
            <.icon class="w-6 h-6" name="hero-globe-alt" />
            <div class="absolute bottom-[5px] right-2 w-[5px] h-[5px] rounded-full bg-red"></div>
          </div>
          <div class="relative w-[50px] h-[50px] p-2 bg-primary flex items-center justify-center rounded-md hover:bg-secondary cursor-pointer">
            <.icon class="w-6 h-6" name="hero-computer-desktop" />
            <div class="absolute bottom-[5px] right-2 w-[5px] h-[5px] rounded-full bg-gray-1"></div>
          </div>
          <%!-- Add more button --%>
          <div class="w-[50px] h-[50px] bg-transparent border border-dashed flex items-center justify-center rounded-md hover:bg-secondary cursor-pointer">
            <.icon class="w-6 h-6" name="hero-plus" />
          </div>
        </div>
        <!-- Pills - For OS services -->
        <div class="grid grid-cols-2 gap-2">
          <div class="w-[120px] bg-primary flex flex-row gap-3 py-2 px-3 items-center rounded-md hover:bg-secondary cursor-pointer">
            <div class="w-[13px] h-[13px] rounded-full bg-yellow"></div>
            <div class="font-main text-sm truncate">DHCP</div>
          </div>
          <div class="w-[120px] bg-primary flex flex-row gap-3 py-2 px-3 items-center rounded-md hover:bg-secondary cursor-pointer">
            <div class="w-[13px] h-[13px] rounded-full bg-red"></div>
            <div class="font-main text-sm truncate">DNS</div>
          </div>
          <div class="w-[120px] bg-primary flex flex-row gap-3 py-2 px-3 items-center rounded-md hover:bg-secondary cursor-pointer">
            <div class="w-[13px] h-[13px] rounded-full bg-gray-1"></div>
            <div class="font-main text-sm truncate">DoH</div>
          </div>
          <div class="w-[120px] bg-primary flex flex-row gap-3 py-2 px-3 items-center rounded-md hover:bg-secondary cursor-pointer">
            <div class="w-[13px] h-[13px] rounded-full bg-green"></div>
            <div class="font-main text-sm truncate">WiFi</div>
          </div>
        </div>
        <!-- Links & Link w/ Icon -->
        <div class="grid grid-cols-2 gap-2">
          <div class="flex items-center justify-center gap-1 bg-primary hover:bg-secondary p-2 transition-all cursor-pointer rounded-md duration-150">
            <.icon class="w-4 h-4" name="hero-list-bullet" />
            <div class="font-main truncate text-xs">View All</div>
          </div>
          <div class="flex items-center justify-center gap-1 bg-primary hover:bg-secondary p-2 transition-all cursor-pointer rounded-md duration-150">
            <.icon class="w-4 h-4" name="hero-no-symbol" />
            <div class="font-main truncate text-xs">Block List</div>
          </div>
          <div class="flex items-center justify-center gap-1 bg-primary hover:bg-secondary p-2 transition-all cursor-pointer rounded-md duration-150">
            <.icon class="w-4 h-4" name="hero-circle-stack" />
            <div class="font-main truncate text-xs">Log Backups</div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
