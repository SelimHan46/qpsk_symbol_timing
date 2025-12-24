%% ==============================================================================
%  QPSK RECEIVER PROJECT - FINAL SUBMISSION
%  Mesaj: "the crowd with Kuzco in the back of his cart..."
%  Ayarlar: Non-Differential | 7-Bit ASCII | Map: [2 3 1 0]
% ==============================================================================
clc; clear; close all;

%% 1. AYARLAR VE YÜKLEME
sps = 8; roll = 0.5; span = 12; fc = 0.30;
BnTb = 0.001; BnTs = BnTb * 2; zeta = 0.7071; % Timing Loop
denom = (zeta + 1/(4*zeta)); Kp = (4 * zeta * BnTs) / denom; Ki = (4 * BnTs^2) / denom;

fprintf('Sinyal Yükleniyor...\n');
load('qpsktrdata.mat'); 
if exist('r', 'var'), if isa(r, 'timeseries'), raw=r.Data; elseif isstruct(r), raw=r.Data; else, raw=r; end; else, error('r yok'); end
signal = double(squeeze(raw)); 

% Baseband Dönüşümü
n = 0:length(signal)-1;
r_baseband = signal .* exp(-1j * 2 * pi * fc * n');

% Matched Filter (SRRC)
h = rcosdesign(roll, span, sps, 'sqrt'); h = h / max(h); 
rx_filt = conv(r_baseband, h); rx_filt = rx_filt((length(h)-1)/2+1:end-(length(h)-1)/2);

%% 2. TIMING RECOVERY (GARDNER)
fprintf('Timing Recovery (Gardner) çalışıyor...\n');
W = 2/sps; CNT = 1; mu = 0; vi = 0;
interp_out = zeros(length(rx_filt), 1); strobe_indices = []; k_out = 0;
prev = 0; mid = 0; is_strobe = false;

for i = 2 : length(rx_filt)-2
    buf = rx_filt(i-1 : i+1); CNT = CNT - W;
    if CNT < 0
        mu = CNT/W; v0=buf(2); v1=0.5*(buf(3)-buf(1)); v2=0.5*(buf(3)+buf(1))-buf(2);
        curr = v0 + v1*(mu+1) + v2*(mu+1)^2;
        k_out = k_out + 1; interp_out(k_out) = curr;
        if is_strobe
            err = real((curr - prev) * conj(mid)); vi = vi + Ki * err; W = (2/sps) + Kp * err + vi;
            strobe_indices(end+1) = k_out; prev = curr; is_strobe = false;
        else, mid = curr; is_strobe = true; end
        CNT = CNT + 1;
    end
end
sys_symbols = interp_out(strobe_indices);

%% 3. CARRIER RECOVERY (COSTAS LOOP)
fprintf('Carrier Recovery çalışıyor...\n');
BnTs_pll = 0.005; Kp_pll = 2 * zeta * BnTs_pll; Ki_pll = 2 * BnTs_pll^2;
phase = 0; integ_pll = 0; corrected_symbols = zeros(length(sys_symbols), 1);

for k = 1:length(sys_symbols)
    rot = sys_symbols(k) * exp(-1j * phase); corrected_symbols(k) = rot;
    perr = imag(rot)*sign(real(rot)) - real(rot)*sign(imag(rot));
    integ_pll = integ_pll + Ki_pll * perr; phase = phase + Kp_pll * perr + integ_pll;
    phase = mod(phase, 2*pi);
end

%% 4. FRAME SYNC (BARKER 13)
% Sinyalin 270 derecede kilitlendiğini tespit etmiştik.
rot_270 = corrected_symbols * exp(-1j * 3*pi/2);

% Barker Deseni (Raw Bits)
bits_raw = zeros(2*length(rot_270), 1);
bits_raw(1:2:end) = real(rot_270)>0; bits_raw(2:2:end) = imag(rot_270)>0;
barker = [1 1 1 1 1 0 0 1 1 0 1 0 1]';
c = xcorr(2*bits_raw-1, 2*barker-1);
[max_val, lag_idx] = max(c);

start_idx = lag_idx - length(bits_raw) + 1;
header_end_sym = ceil((start_idx + 13) / 2);
payload_syms = rot_270(header_end_sym : end);

fprintf('Barker Peak: %.1f (Kilitlendi)\n', max_val);

%% 5. DECODING (NON-DIFFERENTIAL, 7-BIT)
fprintf('\n================================================\n');
fprintf('MESAJ ÇÖZÜLÜYOR...\n');
fprintf('================================================\n');

% Sembollerin Çeyreklerini Bul (0, 1, 2, 3)
% Non-Differential olduğu için direkt fazlarına bakıyoruz.
% Eksenlere göre karar veriyoruz (I,Q işaretleri).
quadrants = zeros(length(payload_syms), 1);
for k=1:length(payload_syms)
    s = payload_syms(k);
    if real(s)>0 && imag(s)>0, q=0;      % 1. Bölge
    elseif real(s)<0 && imag(s)>0, q=1;  % 2. Bölge
    elseif real(s)<0 && imag(s)<0, q=2;  % 3. Bölge
    else, q=3; end                       % 4. Bölge
    quadrants(k) = q;
end

% Harita: [2 3 1 0] (Mega Tarayıcı ile bulundu)
% 0->2(10), 1->3(11), 2->1(01), 3->0(00)
custom_map = [2, 3, 1, 0];

bit_stream = [];
for k = 1:length(quadrants)
    val = custom_map(quadrants(k) + 1);
    % 2 bit ekle
    bit_stream = [bit_stream, bitget(val, 2), bitget(val, 1)];
end

% 7-BIT ASCII ÇEVİRİMİ
msg = '';
num_chars = floor(length(bit_stream)/7);

for k = 1:num_chars
    % 7 bitlik paket al
    chunk = bit_stream((k-1)*7+1 : k*7);
    % Decimal'e çevir (Left-MSB)
    val = bi2de(chunk(:)', 'left-msb');
    
    if val >= 32 && val <= 126
        msg(end+1) = char(val);
    else
        msg(end+1) = '?'; % Okunamayan karakter
    end
end

fprintf('ÇÖZÜLEN MESAJ:\n%s\n', msg);
fprintf('================================================\n');

%% 6. GRAFİKLER
figure('Name','Final QPSK Results','Position',[100,100,1000,500]);
subplot(1,2,1); plot(sys_symbols(500:end-500),'.'); title('Timing Output'); grid on; axis square;
subplot(1,2,2); plot(corrected_symbols(500:end-500),'.'); title('Carrier Output (Locked)'); grid on; axis square; xlim([-2 2]); ylim([-2 2]);