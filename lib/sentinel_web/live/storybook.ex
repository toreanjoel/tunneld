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
    <div class="text-white p-10">
      <div class="grid lg:grid-cols-3 md:grid-cols-2 grid-cols-1 gap-4 items-center justify-items-center">
        <!-- Top Title -->
        <div class="py-2">
          <div class="text-6xl font-medium bg-gradient-to-r from-white to-white bg-clip-text text-transparent">Heading</div>
          <div class="text-2xl">Sub text will go here</div>
        </div>
        <!-- DEVICES -->
        <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-2 gap-4">
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
            <div class="text-sm">_TrojanMorse</div>
            <div class="text-xs">aa:bb:cc:dd:ee:ff</div>
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
            <div class="text-sm">LG TV</div>
            <div class="text-xs">aa:bb:cc:dd:ee:ff</div>
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
            <div class="text-sm">Note 20</div>
            <div class="text-xs">aa:bb:cc:dd:ee:ff</div>
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
            <div class="text-sm">Mac M1</div>
            <div class="text-xs">aa:bb:cc:dd:ee:ff</div>
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
          <div class="w-[50px] h-[50px] opacity-30 bg-transparent border border-dashed flex items-center justify-center rounded-md cursor-pointer">
            <.icon class="w-6 h-6" name="hero-plus" />
          </div>
        </div>
        <!-- Pills - For OS services -->
        <div class="grid grid-cols-2 md:grid-cols-2 gap-2">
          <div class="w-[120px] bg-primary flex flex-row gap-3 py-2 px-3 items-center rounded-md hover:bg-secondary cursor-pointer">
            <div class="w-[13px] h-[13px] rounded-full bg-yellow"></div>
            <div class="text-sm truncate">DHCP</div>
          </div>
          <div class="w-[120px] bg-primary flex flex-row gap-3 py-2 px-3 items-center rounded-md hover:bg-secondary cursor-pointer">
            <div class="w-[13px] h-[13px] rounded-full bg-red"></div>
            <div class="text-sm truncate">DNS</div>
          </div>
          <div class="w-[120px] bg-primary flex flex-row gap-3 py-2 px-3 items-center rounded-md hover:bg-secondary cursor-pointer">
            <div class="w-[13px] h-[13px] rounded-full bg-gray-1"></div>
            <div class="text-sm truncate">DoH</div>
          </div>
          <div class="w-[120px] bg-primary flex flex-row gap-3 py-2 px-3 items-center rounded-md hover:bg-secondary cursor-pointer">
            <div class="w-[13px] h-[13px] rounded-full bg-green"></div>
            <div class="text-sm truncate">WiFi</div>
          </div>
        </div>
        <!-- Links & Link w/ Icon -->
        <div class="grid grid-cols-2 md:grid-cols-3 gap-2">
          <div class="flex items-center justify-center gap-1 bg-primary hover:bg-secondary p-2 transition-all cursor-pointer rounded-md duration-150">
            <.icon class="w-4 h-4" name="hero-list-bullet" />
            <div class="truncate text-xs">View All</div>
          </div>
          <div class="flex items-center justify-center gap-1 bg-primary hover:bg-secondary p-2 transition-all cursor-pointer rounded-md duration-150">
            <.icon class="w-4 h-4" name="hero-no-symbol" />
            <div class="truncate text-xs">Block List</div>
          </div>
          <div class="flex items-center justify-center gap-1 bg-primary hover:bg-secondary p-2 transition-all cursor-pointer rounded-md duration-150">
            <.icon class="w-4 h-4" name="hero-circle-stack" />
            <div class="truncate text-xs">Log Backups</div>
          </div>
        </div>
        <!-- Guage Loader -->
        <div class="grid grid-cols-2 md:grid-cols-2 gap-2">
          <%!-- CPU Example --%>
          <div>
            <%
              # Set the progress percent (you can change this value)
              percent = 55
              radius = 65
              circumference = 2 * :math.pi() * radius
              offset = circumference * (1 - percent / 100)
            %>
            <div class="bg-primary relative w-[120px] rounded-lg">
              <svg class="w-full h-full" viewBox="0 0 170 170">
                <!-- Background circle -->
                <circle
                  cx="85"
                  cy="85"
                  r={radius}
                  class="text-transparent"
                  stroke-width="5"
                  fill="none"
                />
                <!-- Progress circle -->
                <circle
                  cx="85"
                  cy="85"
                  r={radius}
                  class="text-yellow"
                  stroke-width="5"
                  fill="none"
                  stroke-dasharray={circumference}
                  stroke-dashoffset={offset}
                  stroke-linecap="round"
                  style="transform: rotate(-90deg); transform-origin: center;"
                  stroke="currentColor"
                />
              </svg>
              <!-- Hardcoded percent text -->
              <div class="absolute inset-0 flex flex-col items-center justify-center text-lg text-white">
                <%= "#{percent}%" %>
                <div class="text-xs">CPU</div>
              </div>
            </div>
          </div>
          <%!-- RAM Example --%>
          <div>
            <%
              # Set the progress percent (you can change this value)
              percent = 80
              radius = 65
              circumference = 2 * :math.pi() * radius
              offset = circumference * (1 - percent / 100)
            %>
            <div class="bg-primary relative w-[120px] rounded-lg">
              <svg class="w-full h-full" viewBox="0 0 170 170">
                <!-- Background circle -->
                <circle
                  cx="85"
                  cy="85"
                  r={radius}
                  class="text-transparent"
                  stroke-width="5"
                  fill="none"
                />
                <!-- Progress circle -->
                <circle
                  cx="85"
                  cy="85"
                  r={radius}
                  class="text-red"
                  stroke-width="5"
                  fill="none"
                  stroke-dasharray={circumference}
                  stroke-dashoffset={offset}
                  stroke-linecap="round"
                  style="transform: rotate(-90deg); transform-origin: center;"
                  stroke="currentColor"
                />
              </svg>
              <!-- Hardcoded percent text -->
              <div class="absolute inset-0 flex flex-col items-center justify-center text-lg text-white">
                <%= "#{percent}%" %>
                <div class="text-xs">RAM</div>
              </div>
            </div>
          </div>
          <%!-- Storage Example --%>
          <div>
            <%
              # Set the progress percent (you can change this value)
              percent = 44
              radius = 65
              circumference = 2 * :math.pi() * radius
              offset = circumference * (1 - percent / 100)
            %>
            <div class="bg-primary relative w-[120px] rounded-lg">
              <svg class="w-full h-full" viewBox="0 0 170 170">
                <!-- Background circle -->
                <circle
                  cx="85"
                  cy="85"
                  r={radius}
                  class="text-transparent"
                  stroke-width="5"
                  fill="none"
                />
                <!-- Progress circle -->
                <circle
                  cx="85"
                  cy="85"
                  r={radius}
                  class="text-green"
                  stroke-width="5"
                  fill="none"
                  stroke-dasharray={circumference}
                  stroke-dashoffset={offset}
                  stroke-linecap="round"
                  style="transform: rotate(-90deg); transform-origin: center;"
                  stroke="currentColor"
                />
              </svg>
              <!-- Hardcoded percent text -->
              <div class="absolute inset-0 flex flex-col items-center justify-center text-lg text-white">
                <%= "#{percent}%" %>
                <div class="text-xs">Storage</div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
