%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 3D SIMULATION
% MEJ 5/2/11
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function mov = floatBoat3D()

%% define world
world.g = 9.81;
world.rho = 1000;
world.dt = 0.01;

%% set simulation
t0 = randn*100;
world.frames = 1000;
mov = [];
world.t = t0:world.dt:t0+world.frames*world.dt;
world.dx = 0.1;
[world.X world.Y] = meshgrid(-5:world.dx:5,-5:world.dx:5);
world.Z = world.X;
world.water.dw = 0.1;
world.water.w = world.water.dw:world.water.dw:2;

%% water and wind
world.water.Z = zeros(size(world.X));
world.wind.speed = 0.1; %wind speed @19.5m (knots?)
world.wind.dir = 45;
%compute frequency spectrum from 
%Pierson-Moskowitz formula
world.water.Sw = (8.1e-3*world.g^2./(world.water.w.^5)).*exp(-0.74*(world.g*((world.wind.speed*world.water.w).^-1)).^4);
%compute amplitudes of wave spectra
%(http://en.wikipedia.org/wiki/Sea_states
world.water.A = 0.5*sqrt(2*world.water.Sw*world.water.dw);
%compute wave numbers
world.water.k = 100*world.water.w.^2/world.g;
world.water.w = 50*world.water.w;
world.water.Z = zeros(size(world.X));
world.wind.winddir = world.wind.dir*ones(size(world.X));
world.wind.randwind = world.wind.winddir;
%secondary wind speed
world.wind.secSpeed = 20;
%secondary wind source angles
world.wind.secWind = 5:5:90;
world.wind.secWindACoeff1 = -1 + 2*rand(size(world.wind.secWind));
world.wind.secWindACoeff2 = -1 + 2*rand(size(world.wind.secWind));
world.wind.secWindACoeff = zeros(length(world.wind.secWindACoeff1),world.frames+1);
for a = 1:1:length(world.wind.secWindACoeff1)   
    world.wind.secWindACoeff(a,:) = ((world.wind.secWindACoeff2(a)-world.wind.secWindACoeff1(a))/world.frames)*(0:1:world.frames)+world.wind.secWindACoeff1(a);
end
world.water.Sw2 =(8.1e-3*9.81^2./(world.water.w.^5)).*exp(-0.74*(9.81*((world.wind.secSpeed*world.water.w).^-1)).^4);
world.water.A2 = 0.5*sqrt(2*world.water.Sw2*world.water.dw);
world.t02 = randn(size(world.wind.secWind))*100;

%% define boat
boat.x = [0 0 1.25 0 0 0]'; %see Marine Hydrodynamics pg 286 for coord system
boat.v = [0 0 0 0 0 0]';
boat.a = [0 10 0 10 10 0]';
boat.M = [120 0 0 0 0 0;...
          0 120 0 0 0 0;...
          0 0 120 0 0 0;...
          0 0 0 237 -39 -0.4;...
          0 0 0 -39 310 1.4;...
          0 0 0 -0.4 1.4 86];
boat.Minv = inv(boat.M);
boat.sail.x = [0 0 0 0 0 0]';
boat.sail.v = [0 0 0 0 0 0]';
boat.sail.J = 5;
boat.rudder.x = [0 0 0 0 0 0]';
boat.rudder.v = [0 0 0 0 0 0]';
boat.rudder.J = 3;
boat.model = buildBoat();
boat.sail.held = 0;

%% simulation
for frame=1:1:length(world.t)
    %% Sum all the forces on the boat
    boat.F = [0;0;0;0;0;0];
    
    % Gravity
    boat.F = boat.F + -boat.M*[0; 0; world.g; 0; 0; 0];
    % Buoyancy
    boat.F = boat.F + buoyancyForce(boat, world);
    
    % Drag
    boat.F = boat.F + dragForce(boat, world);
    
    % Wave exciting
    
    % From sail and rudder
    %boat.F = boat.F + forceFromSailRudder(boat, world);
    
    
    %% Sail moment
    %boat = forceOnSail(boat,world);
    boat.sail.F = [0 0 0 0 0 0]';
    
    %% Rudder moment
    boat.rudder.F = [0 0 0 0 0 0]';
    
    %% Update boat state
    boat = updateBoatState(boat, world);
    
    %% Update water state
    world = updateWaterState(world, frame);
    
    %% Render frame
    drawFrame(boat, world);
    mov = recordFrame(mov,frame,25,world.dt);   % save movie frame
    pause(world.dt);
    
    100*round2(frame/world.frames,0.01)   % print percent complete
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% force on sail (human + wind)
    function boat = forceOnSail(boat, world)
        SailDrag = -50*boat.sail.v(6);
        if ~boat.sail.held 
            Fvec = forceFromSailRudder(boat,world);
        else
            Fvec = forceFromSailRudder(boat,world);
            if boat.sail.x(6)*Fvec(6) > 0 
                Fvec = [0 0 0 0 0 0]';
                SailDrag = 0;
                boat.sail.a = [0 0 0 0 0 0]';
                boat.sail.v = [0 0 0 0 0 0]';
            end
        end
        
        boat.sail.F = [0 0 0 0 0 Fvec(6)+SailDrag]';

%% sail + rudder force
    function F = forceFromSailRudder(boat, world)
        c = cosd(boat.x(6));
        s = sind(boat.x(6));
        R = [c s; -s c];
        V = R*boat.v(1:2);
        
        % velocity of water is velocity of boat
        v_water = V(1);
        % velocity of wind
        windV = world.wind.speed*R*[cosd(world.wind.dir); sind(world.wind.dir)];
        v_wind_apparent = [V(1) + windV(1); V(2) + windV(2)];
        v_wind = sqrt(v_wind_apparent(1)^2 + v_wind_apparent(2)^2);
        % sail angle relative to boat
        sail_angle = -boat.sail.x(6);
        % rudder angle relative to boat
        rudder_angle = 5;
        % water speed direction relative to boat
        water_angle = 0;
        % apparent wind angle (relative to boat)
        wind_angle = atand(v_wind_apparent(2)/v_wind_apparent(1));
        if isnan(wind_angle)
            wind_angle = 0;
        end
        
        % using Tim's function
        force_on_boat = torques(v_water, v_wind, sail_angle, rudder_angle, water_angle, wind_angle);
        % surely need lift force????
        F = [force_on_boat(1) force_on_boat(2) 0 -force_on_boat(3) -force_on_boat(4) force_on_boat(5)]';

%% drag force
    function F = dragForce(boat, world)
        [A Mx My] = submergedAreas(boat, world);
        % need to be velocities in local coords
        c = cosd(boat.x(6));
        s = sind(boat.x(6));
        R = [c s; -s c];
        V = R*boat.v(1:2);
        F = 3*[-500*A*V(1) -5000*A*V(2) -5000*A*boat.v(3) -3000*A*boat.v(4) -3000*A*boat.v(5) -300*A*boat.v(6)]';

%% buoyancy force
    function F = buoyancyForce(boat, world)
        [A Mx My] = submergedAreas(boat, world);
        F = [0 0 world.g*world.rho*A -100*world.g*world.rho*My -100*world.g*world.rho*Mx 0]';
        
    function [As MomentAsX MomentAsY] = submergedAreas(boat, world)
        % get world positions of hull vertices
        hull = get_hull_global(boat);
        vertices = hull.model.vertices;
%         faces = hull.model.faces;
%         %all forces taken wrt local boat coords
%         %vertices in order of going down the boat
%         leftVertices = [vertices(2,:);...   %front top left
%                         vertices(1,:);...   %front bottom left
%                         vertices(8,:);...   %back bottom left
%                         vertices(7,:)];     %back top left
%         %and equivalent ones on the right side of boat
%         rightVertices = [vertices(3,:);...  %front top right
%                          vertices(4,:);...  %front bottom right
%                          vertices(5,:);...  %back bottom right
%                          vertices(6,:)];    %back top right
%         divisionWidth = 0.1;

        
        Xmesh = world.X;
        Ymesh = world.Y;
        
        %original data points (bottom vertices)
        x = vertices(:,1);
        y = vertices(:,2);
        z = vertices(:,3);
        
        % create a mesh of boat
        F = TriScatteredInterp(x,y,z);
        Zmesh = F(Xmesh,Ymesh);
        
        % find difference from water
        Zw = world.water.Z;
        
        Zdiff = Zw-Zmesh;
        Zdiff(isnan(Zdiff)) = 0;
        Zdiff(Zdiff < 0) = 0;

        As = int_2D_tabulated(Xmesh, Ymesh, Zdiff);
        if As < 0
            As = 0;
        end
        
        % moments
        xDiff = Xmesh - boat.x(1)*ones(size(Xmesh));
        MomentAsX = int_2D_tabulated(Xmesh, Ymesh, Zdiff.*xDiff);
        yDiff = Ymesh - boat.x(2)*ones(size(Ymesh));
        MomentAsY = int_2D_tabulated(Xmesh, Ymesh, Zdiff.*yDiff);
        
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Double integration
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        function V = int_2D_tabulated(X, Y, Z )
                 V = trapz( Y(:,1), (trapz(X(1,:),Z, 2)) );

        
             
         
        
    
        function hull = get_hull_global(boat)
            % translate to current position
            hull = transformObject(boat.model.hull,boat.x);
            
        

%% simulate water
    function world = updateWaterState(world, frame)
        Z = zeros(size(world.water.Z));
        %generate some smooth random wind
        world.wind.randwind = (world.wind.randwind - 10 + (20).*rand(size(world.wind.winddir)))/2; %average with prev rand wind
        %wind filter
        wf = zeros(160/world.wind.speed)/(160/world.wind.speed);
        dir = filter2(wf, world.wind.winddir + world.wind.randwind); %apply smoothing filter
        %generate main wave source
        Z = 0.01*generateWaves(0.1*world.water.w, world.water.Z, world.X, world.Y, ...
                        world.water.A, world.water.k, dir, world.t(frame));
        %now add waves from a different wind source
        for j=1:1:length(world.wind.secWind)
           t2 = world.t02(j):world.dt:world.t02(j)+world.frames*world.dt;
           dir = dir + world.wind.secWind(j)*ones(size(dir));
           Z = generateWaves(1*world.water.w, Z, world.X, world.Y,...
                        12*world.wind.secWindACoeff(j,frame).*world.water.A2, 10*world.water.k, dir, t2(frame));
        end
        wf = ones(160/40)/(160/40)^2;
        world.water.Z = filter2(wf, Z);
        
%% update boat state
    function boat = updateBoatState(boat, world)
        
        %sail
        boat.sail.a = (1/boat.sail.J)*boat.sail.F;
        boat.sail.v = boat.sail.v + world.dt*boat.sail.a;
        boat.sail.x = boat.sail.x + world.dt*boat.sail.v;
        
        %rudder
        boat.rudder.a = (1/boat.rudder.J)*boat.rudder.F;
        boat.rudder.v = boat.rudder.v + world.dt*boat.rudder.a;
        boat.rudder.x = boat.rudder.x + world.dt*boat.rudder.v;
        
                
        %hull
        boat.a = boat.Minv*boat.F;
        boat.v = boat.v + world.dt*boat.a;
        boat.x = boat.x + world.dt*boat.v;
        
        
        


%% draw frame
    function drawFrame(boat, world)
        figure(1); clf; % clear last frame from figure
        
                
        % render water
        m = mesh(world.X,world.Y,world.water.Z);
        set(m,'FaceLighting','phong','FaceColor','interp','AmbientStrength',0.5)
        colormap winter
        shading interp
        

        rudder = transformObject(boat.model.rudder, boat.rudder.x-[0 0 0 0 0 boat.x(6)]');
        %sail = transformObject(boat.model.sail,boat.sail.x-[0 0 0 0 0 boat.x(6)]');
        sail = transformObject(boat.model.sail,boat.sail.x);
        fullboat.model = combine(boat.model.hull.model,rudder.model,sail.model);
        fullboat.transVector = boat.model.hull.transVector;
        fullboat = transformObject(fullboat,boat.x);
        % render the boat
        renderpatch(fullboat.model);
        
        light('position',[-10,10,10])
        axis([-6 6 -6 6 -6 6]);
        view(60,20);

        
%% record movie
    function M = recordFrame(M,i,fps,dt)
        if mod(i,(1/fps)/dt) == 0
            set(gca,'nextplot','replacechildren')
            if isempty(M)
                P(1) = getframe(gcf);
                M = P;
            else
                M(end + 1) = getframe(gcf);
            end
        end