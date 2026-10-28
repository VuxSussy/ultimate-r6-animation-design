# Ultimate R6 Animation Design

Skill cho Claude để thiết kế, sửa, chuyển đổi và chạy animation R6 trên Roblox. Mục tiêu là
animation có lực, dứt khoát, không bị cứng như nhựa và không "khúm núm, rụt rè".

## Thay đổi ở bản này (2026-10-28)

1. **Tìm tham chiếu trước.** Làm animation nào thì tìm bản R6 của động tác đó trước: file của bạn,
   Creator Store (qua Studio MCP), R15 đã chuyển, video. Sau đó đo nó bằng `lune run study` và bắt
   chước theo số đo. Không có bản R6 nào thì theo cách chuyển động của *Ultimate R6 Movement
   System* (Arczi).
2. **Bỏ IK và FK.** Không còn `aim`, không còn giải chân `planted`, không còn `headCounter`, không
   còn module `R6Layers` với 4 chế độ FK+IK/FK/IK/None. Clip phát đúng như tư thế đã key.
3. **Cho phép bộ phận ra khỏi torso một đoạn ngắn.** Mọi bộ phận có `pos` để trượt khỏi khớp.
   Ngân sách đo từ file của Arczi và các gói punch R6: tay tối đa 1,0 stud, chân 1,5 (chủ yếu rút
   lên vào torso thay cho gập gối), đầu 0,15 (chỉ xoay).
4. **Chân không bao giờ bắt chéo.** Chân treo vào một "xương chậu" chỉ xoay 35% theo thân
   (`space = "root"`), và `ground = true` trượt chân để bàn chân luôn chạm sàn. Audit báo khi hai
   chân đè lên nhau hoặc thành hình chữ X nhìn từ bên cạnh hay từ trước.
5. **Audit "rụt rè".** Một cú đấm thẳng phải xoay thân từ 40° trở lên và đưa nắm tay ra ít nhất
   2,8 stud trước gốc. Tham chiếu: thân xoay 30–110°, nắm tay ra 2,3–4,2 stud.
6. **Idle, Walk, Run mới** (`Locomotion.luau`), bắt chước `idle v2`, `walk v3`, `run v4` của
   Arczi (walk lệch tối đa 4,8°, run 3,9°), cùng bộ điều khiển `R6Locomotion`: đi 12 stud/s phát
   walk ở tốc độ/14,5, giữ Shift chạy 27 phát run ở 1,3, đi lùi phát walk ngược, đánh xong hiện thế
   thủ 3 giây rồi về idle.
7. **Dash theo góp ý của bạn:** khi lướt tay vung ra sau; lướt trái/phải không còn giơ tay thủ;
   lướt lùi kết thúc bằng tư thế quỳ chống đất (một chân trước, một chân duỗi sau, tay trước chống
   đất, tay sau vung ra sau).
8. **13 đòn combat làm lại** theo số đo tham chiếu.
9. **Sửa lỗi tay quay cả vòng.** Trước đây R6Clip nội suy xoay theo đường ngắn nhất, nên tay vung
   ra sau (raise −55) về thế thủ (150) bị đi vòng ngược qua đầu (chênh 193°). Giờ R6Clip nội suy
   từng góc có tên. Audit có thêm kiểm tra `overhead` (tay lên quá vai và ra sau lưng) và `export`
   (file xuất ra phát đúng như clip khi Roblox tự nội suy).
10. **Leo, nhảy, rơi, 3 kiểu đáp đất, chạy tường.** Leo, nhảy, rơi và đáp đất bắt chước clip của
   Arczi. Đáp đất chọn theo độ cao rơi: dưới 4 stud đáp nhẹ, 4–15 đáp ngắn, trên 15 đáp dài. Chạy
   tường bắt chước gói "R6 Parkour Animations" trên Creator Store, kèm module `R6WallRun` để chạy
   được thật: đang chạy nhanh mà nhảy sát tường thì bám tường khoảng 1,4 giây, bấm nhảy để bật ra.
11. **Skill ghi lại các lỗi đã gặp** (mục "Mistakes this skill has made" trong SKILL.md), mỗi lỗi
   kèm cách sửa và kiểm tra tự động đang chặn nó. So với bản cũ: jab vươn 3,39 stud (cũ 2,93),
   cross 3,28 (cũ 2,60), thân xoay 50°/58° (cũ 40°/24°), vai tách 0,7 stud (cũ 0).

## Trong thư mục này

| Đường dẫn | Là gì |
|---|---|
| `ultimate-r6-animation-design/` | skill: `SKILL.md`, `references/`, `scripts/`, `tools/`, `evals/` |
| `output/ultimate-r6-animation-design.skill` | gói skill để cài (bấm **Save skill** khi Claude gửi file) |
| `output/R6CombatPack.rbxm` | 24 animation R6 dựng sẵn (13 combat + 11 di chuyển), kéo vào `AnimSaves` của rig |
| `output/eclipse/*.json` | cùng 24 animation, dạng JSON cho tool `save_animation` của Eclipse-Animator-MCP |
| `sword/` | bài test skill: đòn chém kiếm `SwordSlash` (+ `SwordGuard`), làm theo đúng quy trình của skill; `lune run build` ra `sword/out/` (rbxm, JSON Eclipse, preview) |
| `studio/R6TestPlace.rbxl` | place test (có nút chuyển Nắm đấm / Kiếm ở góc trái dưới, hoặc phím 1): modules, StarterCharacter R6, harness, một bức tường để chạy, thang leo, gờ cao 10 và 30 stud |
| `output/preview.html` | xem trước 3D: chạy/dừng, chậm 0.25×, từng khung, vệt tay chân, hit-stop |
| `output/converted/` | 4 clip combat R15 của team đã chuyển sang R6 (bản gốc chỉ được đọc) |

Tài liệu trong `references/`:
- `reference-first.md`: tìm tham chiếu ở đâu, tải an toàn, đo bằng `study`, bắt chước thế nào, và
  bảng số đo của Arczi và các gói punch R6.
- `posing.md`: rig R6, góc có tên, `pos`, ngân sách trượt, chân treo xương chậu, vì sao bỏ IK.
- `weight-and-feel.md`, `combat.md`, `r15-to-r6.md`, `sources.md`.

## Lệnh hay dùng (chạy trong `ultimate-r6-animation-design/tools/`)

Đo mọi animation R6 trong một file để bắt chước theo (thời gian, khung ra đòn, thân xoay/đổ/lao,
độ tách khớp):

```bash
lune run study "~/Downloads/Ultimate R6 Movement System.rbxm"
```

Lấy key pose của một clip tham chiếu ở các khung chọn sẵn, dạng bảng key dán thẳng vào R6Clip:

```bash
lune run study "~/Downloads/Ultimate R6 Movement System.rbxm" "walk v3" --keys=0,6,12,18,24
```

Chạy 192 bài kiểm tra:

```bash
lune run check
```

Dựng lại gói animation, JSON cho Eclipse và trang xem trước:

```bash
lune run build ../../output
```

Chuyển clip R15 trong một file `.rbxm` hoặc `.rbxl` sang R6:

```bash
lune run convert <file.rbxl> ../../output/converted <tên clip>
```

Kiểm tra code Luau bằng selene:

```bash
selene --config selene.toml ../scripts
```

## Đã kiểm tra và chưa kiểm tra

- 192 bài test qua, selene sạch. Cả 24 clip qua audit.
- Nhảy, rơi, leo, chạy tường (playtest): nhảy tại chỗ ra đáp nhẹ (rơi 0,3 stud), gờ 10 stud ra
  đáp ngắn (7,7), gờ 30 stud ra đáp dài (27). Leo phát ở 0,70 (8,4 stud/s ÷ 12) và đứng yên khi
  dừng leo. Chạy tường bám 1,4 giây, đi 37 stud dọc tường. Chưa thử bật ra khỏi tường bằng phím
  nhảy, vì lệnh test không giả lập được phím.
- **Playtest thật** (place Claude_R6_Preview, nhân vật R6). Các số dưới đây đọc từ chính các bộ
  phận trong engine:
  - Combo 4 đòn ra đúng thứ tự, kể cả khi bấm dồn cách nhau 0,12 giây.
  - Jab vươn 3,33 stud, thân xoay −52°; Cross vươn 3,20 stud, thân xoay 54°.
  - Bàn chân luôn sát sàn (lệch tối đa 0,04 stud), hai hông cách nhau 0,97 stud trở lên, chân không chéo.
  - Hit-stop đưa tốc độ clip về 0 rồi trả lại 1. Đang đỡ thì không đánh được.
  - Lướt đi đúng quãng: tới 16,5 stud, lùi 12,5, trái/phải 13,4.
  - Idle/Walk/Run/Stance chuyển đúng theo tốc độ: walk ở 0,83, run ở 1,3, lùi ở −0,83.
- Tư thế dash mới đã dựng trên rig và xem trong Studio (lướt tới, lướt lùi lúc quỳ, lướt trái).
  Mới xem tư thế từng khung, chưa xem cả clip ở tốc độ thật.
- Không mở được `studio/R6TestPlace.rbxl` trong Studio bằng lệnh (Studio kẹt ở bước mở file), nên
  nội dung test đã được nạp vào place Claude_R6_Preview. Bản cũ cất ở `ServerStorage.OldR6Test_backup`.
- Bản chuyển R15 `SingleCross`: chính clip R15 gốc xoay hông khoảng 90° ở khung 8–13, nên chân R6
  sát nhau 0,6 stud và audit báo. Cần key lại tay mấy khung đó.
