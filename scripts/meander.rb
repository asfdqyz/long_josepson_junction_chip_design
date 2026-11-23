# encoding: utf-8

module SerpentineMeanderSameLength

  def self.to_dbu(ly, value_um)
    (value_um / ly.dbu).round
  end

  def self.arc(cx, cy, r, a1, a2, n)
    pts = []

    n.times do |i|
      t = i.to_f / (n - 1)
      a = a1 + (a2 - a1) * t

      x = cx + r * Math.cos(a)
      y = cy + r * Math.sin(a)

      pts << RBA::Point::new(x.round, y.round)
    end

    pts
  end

  def self.make_horizontal_meander(x1, x2, y0, lanes, spacing, side, n_arc)
    # lanes лучше брать нечетным: 3, 5, 7, ...
    lanes += 1 if lanes.even?

    dir_y = side == "down" ? -1 : 1
    r = spacing / 2.0

    original_length = (x2 - x1).abs.to_f

    # длина всех полукруглых разворотов
    turns_length = (lanes - 1) * Math::PI * r

    # длина каждого прямого горизонтального участка
    straight_length = (original_length - turns_length) / lanes

    if straight_length <= 0
      raise("Meander is impossible: reduce lanes or spacing")
    end

    # центрируем меандр внутри исходной прямой
    x_mid = (x1 + x2) / 2.0
    x_left = (x_mid - straight_length / 2.0).round
    x_right = (x_mid + straight_length / 2.0).round

    pts = []

    # стартовая точка
    pts << RBA::Point::new(x_left, y0)

    (0...(lanes - 1)).each do |i|
      y  = y0 + dir_y * i * spacing
      yn = y0 + dir_y * (i + 1) * spacing
      cy = (y + yn) / 2.0

      if i.even?
        # идем слева направо
        pts << RBA::Point::new(x_right, y)

        # правый U-разворот
        if dir_y == 1
          pts += arc(x_right, cy, r, -Math::PI / 2.0, Math::PI / 2.0, n_arc)
        else
          pts += arc(x_right, cy, r, Math::PI / 2.0, -Math::PI / 2.0, n_arc)
        end

      else
        # идем справа налево
        pts << RBA::Point::new(x_left, y)

        # левый U-разворот
        if dir_y == 1
          pts += arc(x_left, cy, r, -Math::PI / 2.0, -3.0 * Math::PI / 2.0, n_arc)
        else
          pts += arc(x_left, cy, r, Math::PI / 2.0, 3.0 * Math::PI / 2.0, n_arc)
        end
      end
    end

    # последний горизонтальный участок
    y_last = y0 + dir_y * (lanes - 1) * spacing
    pts << RBA::Point::new(x_right, y_last)

    pts
  end

  def self.run
    # ===== НАСТРОЙКИ =====

    lanes = 51
    # число горизонтальных дорожек.
    # Лучше 3, 5, 7, 9.
    # Чем больше lanes, тем компактнее меандр по горизонтали.

    spacing_um = 15
    # расстояние между центрами соседних дорожек в микронах.
    # Должно быть больше ширины проводника.

    width_um = nil
    # nil = взять ширину исходной прямой.
    # Можно задать вручную, например:
    # width_um = 5.0

    side = "up"
    # "up" или "down" — куда строить меандр относительно исходной прямой.

    n_arc = 48
    # гладкость разворотов.
    # 24 — грубее, 48 — нормально, 72 — очень гладко.

    delete_original = true
    # true = удалить исходную прямую.
    # false = оставить исходную прямую и добавить меандр рядом.

    # =====================

    mw = RBA::Application::instance.main_window
    view = mw.current_view

    raise("No layout view is open") if view.nil?

    sel = view.object_selection
    raise("Select one straight horizontal wire first") if sel.empty?

    view.transaction("Create same-length serpentine meander")

    begin
      sel.each do |obj|
        next if obj.is_cell_inst?

        ly = view.cellview(obj.cv_index).layout
        cell = ly.cell(obj.source)
        layer = obj.layer
        shape = obj.shape

        next if shape.is_text?

        box = shape.bbox

        dx = box.width
        dy = box.height

        if dx <= dy
          puts("Skipped: selected shape is not a horizontal wire")
          next
        end

        x1 = box.left
        x2 = box.right
        y0 = (box.bottom + box.top) / 2

        spacing = to_dbu(ly, spacing_um)

        width =
          if width_um.nil?
            dy
          else
            to_dbu(ly, width_um)
          end

        if spacing <= width
          raise("spacing_um must be larger than wire width")
        end

        pts = make_horizontal_meander(
          x1,
          x2,
          y0,
          lanes,
          spacing,
          side,
          n_arc
        )

        path = RBA::Path::new(pts, width)

        # ВАЖНО:
        # Вставляем Polygon, а не Path,
        # чтобы не было центральной линии.
        poly = path.polygon
        cell.shapes(layer).insert(poly)

        shape.delete if delete_original
      end

    ensure
      view.commit
    end
  end
end

SerpentineMeanderSameLength.run