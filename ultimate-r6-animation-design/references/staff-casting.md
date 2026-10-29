# Tham khảo chuyển động pháp sư dùng trượng

## Nguồn đã mở và quan sát

**MythforgeGames — Wand / Magic staff / Mage Animations Pack**
Video tác giả: https://www.youtube.com/watch?v=jISAbyZNVjg
Trang pack: https://www.fab.com/listings/ff47494c-99a5-4ac4-83ad-59e212acc8b9
Bài giới thiệu của tác giả: https://forums.unrealengine.com/t/talesofgalendora-wand-magic-staff-mage-animation-pack/2658761

Đã xem chuyển động trong trình duyệt và dừng tại các mốc khoảng 7, 12, 17, 22 giây của montage 32 giây. Video hiện nhiều diễn viên cùng lúc; đây không phải phép đo keyframe của một clip riêng.

Quan sát có thể dùng: tư thế cầm trượng đứng cạnh thân; vai/ngực mở lệch, chân không đứng song song cứng; thân có nghiêng/chuyển trọng tâm; tay cầm dụng cụ và tay còn lại không chuyển động như một khối; có biến thể hạ trọng tâm mạnh. Không phải mọi diễn viên trong montage đều làm cùng động tác, và video này có cả wand và staff.

**R6 Magic Casting Animation Pack — RobloxAnimations**
https://robloxanimations.com/product/magic-casting-animation-pack-r6
Đã kiểm tra phiên bản R6: phần xem trước công khai chỉ có thumbnail, không có video R6 để đo trong trang này. Vì vậy không dùng tên pack hay mô tả bán hàng làm bằng chứng đã xem chuyển động R6. Không mua hoặc tải file được cấp phép.

**9CG — Mage Animation Pack for Unreal Engine**
https://www.youtube.com/watch?v=jBJqzE7r8BY
Đã mở đối chiếu nhưng các đoạn quan sát có Combo Attack, Attack Air to Floor và Walk Combat; không dùng những đoạn cận chiến đó làm mẫu cho bộ phép tầm xa này.

## Cách chuyển thể thành R6

Đây là key mới lấy cảm hứng từ tạo hình và sự lệch pha của nguồn humanoid, không phải retarget hay sao chép key của pack. Không có số đo góc hoặc thời gian release chính xác của nguồn. Các con số dưới đây là lựa chọn thiết kế cho bộ R6 này.

| Đòn | Tạo hình mới | Nạp / Cast / Giữ / kết thúc key ở 60 FPS |
|---|---|---|
| Bolt | Dụng cụ cạnh vai, ngực xoay ngược nhẹ rồi chỉ đầu trượng; tay trái mở ra cạnh thân | nạp đến f12 / Cast18 / giữ10f / key50 + head trail2 |
| Sigil Volley | Tay trái đi 3 tư thế vòng cung quanh vùng trước ngực; trượng giữ bên thân rồi hướng ngắm | nạp đến f18 / Cast24 / giữ10f / key58 +2 |
| Gather Orb | Hai tay thu vào vùng ngực, hạ trọng tâm rồi đẩy phép; thân đổi từ -18 sang +18 độ | nạp đến f22 / Cast28 / giữ12f / key64 +2 |
| Ritual Beam | Hai tay nâng cao, trượng dựng trước vai, thân ngả nhẹ rồi dồn về phía phép và giữ kênh | nạp đến f30 / Cast38 / giữ20f / key84 +2 |

Các gesture vẽ ấn/thu phép/giữ kênh là cách diễn giải thiết kế, không gán chúng cho một clip có tên cụ thể trong video. Khác bản cũ: không dùng cùng 1 tạo hình Cast cho cả 4 đòn; tay trái có vai trò và nhịp riêng; giữ các mối nối khớp để chơi combo. Tổng 264f = 4,4 giây, dài hơn bản 188f để đọc được gesture và nạp phép.

Giới hạn R6: không có khuỷu tay/cổ tay/ngón tay. Vòng ấn được gợi bằng vai và trượt tay ngắn, không mô phỏng cử chỉ ngón tay. Giữ trượng mẫu cứng trong tay phải, đầu phép ở (0,-1,-3.2) trong không gian Right Arm.

## Quy tắc dùng lại trong skill

Khi làm ranged staff casting, không lấy jab/cross/sword slash làm reference ngôn ngữ động tác. Tìm video hoặc clip mage thật trước. Nếu chỉ đọc trang sản phẩm thì phải nói chưa xem chuyển động. Nếu chỉ có nguồn humanoid thì ghi rõ phần nào quan sát, phần nào tự đặt và giới hạn chuyển thể R6. Marker Cast là nhả phép; va chạm là sự kiện projectile đến mục tiêu. Kiểm tra tư thế tay tự do, loading, chuyển trọng tâm, hướng đầu trượng, giữ kênh và hồi phục; audit cấu trúc không tự chứng minh dáng mage đúng.
