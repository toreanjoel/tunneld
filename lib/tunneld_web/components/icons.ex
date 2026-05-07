defmodule TunneldWeb.Icons do
  @moduledoc """
  Inline SVG icons matching the React prototype's Lucide-style set.
  Self-hosted — no CDN dependency.
  """
  use Phoenix.Component

  attr :size, :integer, default: 18
  attr :class, :string, default: nil
  attr :rest, :global

  def log_out(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class={@class} {@rest}><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>
    """
  end

  attr :size, :integer, default: 18
  attr :class, :string, default: nil
  attr :rest, :global

  def eye(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class={@class} {@rest}><path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></svg>
    """
  end

  attr :size, :integer, default: 18
  attr :class, :string, default: nil
  attr :rest, :global

  def eye_slash(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class={@class} {@rest}>
      <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-10-7-10-7a18.45 18.45 0 0 1 5.06-5.94" />
      <path d="M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 10 7 10 7a18.5 18.5 0 0 1-2.16 3.19" />
      <line x1="1" y1="1" x2="23" y2="23" />
    </svg>
    """
  end

  attr :size, :integer, default: 18
  attr :class, :string, default: nil
  attr :rest, :global

  def settings(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class={@class} {@rest}><path d="M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09a1.65 1.65 0 0 0 1.51-1 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33h0a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82v0a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>
    """
  end

  attr :size, :integer, default: 18
  attr :class, :string, default: nil
  attr :rest, :global

  def power(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class={@class} {@rest}><path d="M18.36 6.64a9 9 0 1 1-12.73 0"/><line x1="12" y1="2" x2="12" y2="12"/></svg>
    """
  end

  attr :size, :integer, default: 18
  attr :class, :string, default: nil
  attr :rest, :global

  def cpu(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class={@class} {@rest}><rect x="4" y="4" width="16" height="16" rx="2"/><rect x="9" y="9" width="6" height="6"/><line x1="9" y1="2" x2="9" y2="4"/><line x1="15" y1="2" x2="15" y2="4"/><line x1="9" y1="20" x2="9" y2="22"/><line x1="15" y1="20" x2="15" y2="22"/><line x1="20" y1="9" x2="22" y2="9"/><line x1="20" y1="14" x2="22" y2="14"/><line x1="2" y1="9" x2="4" y2="9"/><line x1="2" y1="14" x2="4" y2="14"/></svg>
    """
  end

  attr :size, :integer, default: 18
  attr :class, :string, default: nil
  attr :rest, :global

  def hard_drive(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class={@class} {@rest}><line x1="22" y1="12" x2="2" y2="12"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/><line x1="6" y1="16" x2="6.01" y2="16"/><line x1="10" y1="16" x2="10.01" y2="16"/></svg>
    """
  end

  attr :size, :integer, default: 18
  attr :class, :string, default: nil
  attr :rest, :global

  def database(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class={@class} {@rest}><ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M21 12c0 1.66-4 3-9 3s-9-1.34-9-3"/><path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5"/></svg>
    """
  end

  attr :size, :integer, default: 18
  attr :class, :string, default: nil
  attr :rest, :global

  def thermometer(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class={@class} {@rest}><path d="M14 14.76V3.5a2.5 2.5 0 0 0-5 0v11.26a4 4 0 1 0 5 0z"/></svg>
    """
  end

  attr :size, :integer, default: 18
  attr :class, :string, default: nil
  attr :rest, :global

  def server(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class={@class} {@rest}><rect x="2" y="2" width="20" height="8" rx="2"/><rect x="2" y="14" width="20" height="8" rx="2"/><line x1="6" y1="6" x2="6.01" y2="6"/><line x1="6" y1="18" x2="6.01" y2="18"/></svg>
    """
  end

  attr :size, :integer, default: 18
  attr :class, :string, default: nil
  attr :rest, :global

  def monitor(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class={@class} {@rest}><rect x="2" y="3" width="20" height="14" rx="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/></svg>
    """
  end

  attr :size, :integer, default: 18
  attr :class, :string, default: nil
  attr :rest, :global

  def zap(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class={@class} {@rest}><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>
    """
  end

  attr :size, :integer, default: 18
  attr :class, :string, default: nil
  attr :rest, :global

  def icons_link(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class={@class} {@rest}><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/></svg>
    """
  end

  attr :size, :integer, default: 18
  attr :class, :string, default: nil
  attr :rest, :global

  def plus(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class={@class} {@rest}><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
    """
  end

  attr :size, :integer, default: 18
  attr :class, :string, default: nil
  attr :rest, :global

  def chevron_right(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class={@class} {@rest}><polyline points="9 18 15 12 9 6"/></svg>
    """
  end

  attr :size, :integer, default: 18
  attr :class, :string, default: nil
  attr :rest, :global

  def x(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class={@class} {@rest}><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
    """
  end

  attr :size, :integer, default: 18
  attr :class, :string, default: nil
  attr :rest, :global

  def check(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class={@class} {@rest}><polyline points="20 6 9 17 4 12"/></svg>
    """
  end

  attr :size, :integer, default: 18
  attr :class, :string, default: nil
  attr :rest, :global

  def copy(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class={@class} {@rest}><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
    """
  end

  attr :size, :integer, default: 18
  attr :class, :string, default: nil
  attr :rest, :global

  def pencil(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class={@class} {@rest}><path d="M17 3a2.85 2.85 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3z"/></svg>
    """
  end

  attr :size, :integer, default: 18
  attr :class, :string, default: nil
  attr :rest, :global

  def more(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class={@class} {@rest}><circle cx="12" cy="12" r="1.5"/><circle cx="19" cy="12" r="1.5"/><circle cx="5" cy="12" r="1.5"/></svg>
    """
  end

  attr :size, :integer, default: 18
  attr :class, :string, default: nil
  attr :rest, :global

  def arrow_left(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class={@class} {@rest}><line x1="19" y1="12" x2="5" y2="12"/><polyline points="12 19 5 12 12 5"/></svg>
    """
  end

  attr :size, :integer, default: 18
  attr :class, :string, default: nil
  attr :rest, :global

  def tag(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class={@class} {@rest}><path d="M20.59 13.41 13.41 20.59a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z"/><line x1="7" y1="7" x2="7.01" y2="7"/></svg>
    """
  end

  attr :size, :integer, default: 18
  attr :class, :string, default: nil
  attr :rest, :global

  def trash(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class={@class} {@rest}><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
    """
  end

  attr :size, :integer, default: 18
  attr :class, :string, default: nil
  attr :rest, :global

  def refresh(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class={@class} {@rest}><polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/></svg>
    """
  end
end
