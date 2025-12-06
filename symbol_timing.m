
Ns = 8;          % Örnekleme/bit
fc = 0.3;        % Taşıyıcı frekansı
alpha = 0.5;     % SRRC fazla bant genişliği (excess bandwidth)
span = 12;       % SRRC filtre uzunluğu (sembol cinsinden)
sps = 4;         % Sembol başına örnek sayısı (8/2 = 4)

% Dosyayı yükle 
load('qpsktrdata.mat');

% whos

% r

% Sinyali al
signal = r.Data;

% 3D array'i düzleştir (flatten) - 1D yap
signal = squeeze(signal);  % [1x1x17989] → [17989x1]


% Taşıyıcıyı kaldır (I ve Q'ya ayır)

% Zaman indeksleri: 0,1,2,3,...
% Yüksek frekanstaki sinyali baseband'e (düşük frekansa) çekmek
n = 0:length(signal)-1;

r_i = signal .* cos(2*pi*fc*n)';

r_q = signal .* sin(2*pi*fc*n)';

% SRRC Matched Filter
h = rcosdesign(alpha, span, sps, 'sqrt');     % SRRC filtre katsayıları
h = h / max(abs(h));                          % Normalize et (max=1)
% Filtrenin en büyük değeri 1 olsun

% Filtre gecikme yaratır
% Ortadaki orijinal sinyali al
delay = (length(h)-1)/2;  



% Filtreleme
mf_i = conv(r_i, h);
mf_q = conv(r_q, h);

% conv() fonksiyonu filtre uygularken başa ve sona sıfırlar ekler.
% Bunlar bizim gerçek verimiz değil

mf_i = mf_i(delay+1:end-delay);
mf_q = mf_q(delay+1:end-delay);

% Downsampling (8 samples/symbol → 2 samples/symbol)
mf_i_ds = mf_i(1:4:end);  % Her 4. örneği al (8→2 samples/symbol)
mf_q_ds = mf_q(1:4:end);  % TED için 2 samples/symbol gerekli


% ortalama gücünün 1 civarında olması gerekir.
rms_power = sqrt(mean(mf_i_ds.^2 + mf_q_ds.^2));
mf_i_ds = mf_i_ds / rms_power;
mf_q_ds = mf_q_ds / rms_power;

%  8 samples/symbol → 2 samples/symbol (diyagramda N÷2 bloğu)

% Timing PLL Parametreleri
normalized_bandwidth = 0.01;    % BnTs (normalize gürültü bant genişliği)
damping_factor = 0.7071;        % zeta (sönümleme faktörü)

% Loop Filter Kazançları
theta = normalized_bandwidth / (damping_factor + 1/(4*damping_factor));
d = 1 + 2*damping_factor*theta + theta^2;
K1 = (4*damping_factor*theta) / d;
K2 = (4*theta^2) / d;




% K1 → Anlık hatayı düzeltir (proportional)
% Büyükse: Hızlı tepki verir ama sallanır
% Küçükse: Yavaş ama stabil


% K2 (Integral gain) → Hatayı düzeltme gücü
% K2 → Birikmiş hatayı düzeltir (integral)

% Büyükse: Hatayı hızlı sıfırlar
% Küçükse: Yavaş düzeltir

% Timing Loop için hazırlık
N = length(mf_i_ds);                    % Kaç örnek var?
max_symbols = ceil(N/2) + 100;          % Maksimum sembol sayısı

% Çıkış dizileri
decisions_i = zeros(max_symbols, 1);
decisions_q = zeros(max_symbols, 1);
mu_history = zeros(max_symbols, 1);


% Başlangıç değerleri
mu = 0.0;           % Kesirli interpolasyon aralığı (0-1 arası, μ okuruz)
                    % İki örnek arasında neredeysek (0=başta, 1=sonda)
                    
W = 1.0;            % NCO kontrol kelimesi (sayaç hızı)
                    % Loop filter bu değeri ayarlayarak timing'i düzeltir
                    
vi = 0;             % Integral state (loop filter'ın hafızası)
                    % Geçmişteki hataların birikmiş toplamı
                    % Başlangıçta 0 (henüz hata birikmedi)
                    
symbol_count = 0;   % Bulunan sembol sayısı (sayaç)
                    % Her strobe olduğunda +1 artacak


 % bir defaya mahsus değil tum n ler için tum ornakerli for da yap her donus için yap

 % Farrow interpolator için buffer
buffer_i = zeros(4, 1);
buffer_q = zeros(4, 1);

% TED için önceki örnek
prev_i = 0;
prev_q = 0;

idx = 1; 



 % Her örnek için çalış!
while idx <= N-3 && symbol_count < max_symbols
    
   
    buffer_i = [mf_i_ds(idx); mf_i_ds(idx+1); mf_i_ds(idx+2); mf_i_ds(idx+3)];
    buffer_q = [mf_q_ds(idx); mf_q_ds(idx+1); mf_q_ds(idx+2); mf_q_ds(idx+3)];
    
   
    % v0, v1, v2 katsayıları hesapla
    v0_i = buffer_i(2);
    v0_q = buffer_q(2);
    
    v1_i = 0.5 * (buffer_i(3) - buffer_i(1));
    v1_q = 0.5 * (buffer_q(3) - buffer_q(1));
    
    v2_i = 0.5 * (buffer_i(3) + buffer_i(1)) - buffer_i(2);
    v2_q = 0.5 * (buffer_q(3) + buffer_q(1)) - buffer_q(2);
    
    % İnterpolasyon: y(mu) = v0 + v1*mu + v2*mu^2
    interp_i = v0_i + v1_i*mu + v2_i*mu^2;
    interp_q = v0_q + v1_q*mu + v2_q*mu^2;
    
  
    mu = mu - W;

    % Underflow kontrolü
    if mu < 0
        mu = mu - floor(mu);  % Doğru modulo-1: [0,1) aralığına getir
        strobe = 1;
    else
        strobe = 0;
    end
       
    if strobe
        symbol_count = symbol_count + 1;
        
       
        decisions_i(symbol_count) = sign(interp_i);
        decisions_q(symbol_count) = sign(interp_q);
        
        % TED (Early-Late Timing Error Detector)
        % e[k] = (y[k] - y[k-1]) * d[k]
        ted_i = (interp_i - prev_i) * decisions_i(symbol_count);
        ted_q = (interp_q - prev_q) * decisions_q(symbol_count);
        ted_out = ted_i + ted_q;

        % ★ RICE: TED LİMİT
        ted_out = max(min(ted_out, 2.0), -2.0);
        
        % LOOP FILTER (PI Controller)
        vp = K1 * ted_out;              % Proportional
        vi = vi + K2 * ted_out;         % Integral
        
        % ★ RICE: INTEGRATOR LİMİT
        vi = max(min(vi, 0.5), -0.5);

        W = 1.0 + vp + vi;              % NCO kontrol güncelle

        % ★ RICE: NCO LİMİT
        W = max(min(W, 1.5), 0.5);
        
        % MU history kaydet 
        mu_history(symbol_count) = mu;
        
        % Önceki örnekleri güncelle (TED için)
        prev_i = interp_i;
        prev_q = interp_q;
    end
    
    idx = idx + 1;  % Bir sonraki örneğe
end

fprintf('Toplam %d sembol bulundu.\n', symbol_count);
                  